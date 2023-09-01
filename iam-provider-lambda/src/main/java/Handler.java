import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPResponse;
import com.google.gson.Gson;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.IntStream;
import java.util.stream.Stream;
import lombok.extern.slf4j.Slf4j;
import software.amazon.awssdk.services.ssm.SsmClient;
import software.amazon.awssdk.services.ssm.model.GetParameterRequest;
import software.amazon.awssdk.services.ssm.model.GetParameterResponse;
import software.amazon.awssdk.services.ssm.model.ParameterNotFoundException;

@Slf4j
public class Handler implements RequestHandler<APIGatewayV2HTTPEvent, APIGatewayV2HTTPResponse> {
  private static final APIGatewayV2HTTPResponse UNAUTHORIZED_RESPONSE =
      APIGatewayV2HTTPResponse.builder().withStatusCode(403).build();
  private static final Pattern BEARER_PATTERN = Pattern.compile("Bearer\\s+(\\w+)");
  private static final String AUTHORIZATION = "Authorization";
  private static final String TOKEN_PARAM = "TOKEN_PARAM";
  private static final String REGION_PARAM = "REGION";
  private static final String AWS_ROLE_ARN = "aws/roleArn";
  private static final String KUBECONFIG_PARAM = "/control-plane/kubeconfig";
  private static final String AWS_SHARED_CREDENTIALS_FILE = "AWS_SHARED_CREDENTIALS_FILE";
  private static final String AWS_CONFIG_FILE = "AWS_CONFIG_FILE";
  private static final String PATCH_TYPE = "JSONPatch";
  private static final String VOLUME_NAME = "aws-config-credentials";
  private final Gson gson = new Gson();
  private final SsmClient ssmClient = SsmClient.create();
  private KubernetesSecretsClient kubernetesSecretsClient;
  private AwsConfigFilesProvider configFilesProvider;
  private String token;
  private String region;

  private void setConfigFilesProvider() {
    if (configFilesProvider == null) {
      this.configFilesProvider = AwsConfigFilesProvider.awsConfigFilesProvider();
    }
  }

  private void setKubernetesSecretsClient() {
    if (kubernetesSecretsClient == null) {
      try {
        GetParameterRequest request =
            GetParameterRequest.builder().name(KUBECONFIG_PARAM).withDecryption(true).build();
        GetParameterResponse response = ssmClient.getParameter(request);
        this.kubernetesSecretsClient =
            KubernetesSecretsClient.kubernetesSecretsClient(response.parameter().value());
        log.info("Parameter {} found, client initialized", KUBECONFIG_PARAM);
      } catch (ParameterNotFoundException e) {
        log.warn("Parameter {} is not initialized", KUBECONFIG_PARAM);
      }
    }
  }

  private void setToken(String paramName) {
    if (token == null) {
      GetParameterRequest request =
          GetParameterRequest.builder().name(paramName).withDecryption(true).build();
      GetParameterResponse response = ssmClient.getParameter(request);
      this.token = response.parameter().value();
    }
  }

  private APIGatewayV2HTTPResponse success(AdmissionReview response) {
    return APIGatewayV2HTTPResponse.builder()
        .withStatusCode(200)
        .withBody(gson.toJson(response))
        .build();
  }

  private AdmissionReview pass(AdmissionReview request) {
    return AdmissionReview.response(
        AdmissionReview.Response.builder().allowed(true).uid(request.request().uid()).build());
  }

  private List<JSONPatchRecord> containerUpdateRecords(
      int containerIndex,
      List<ContainerEnvSpec> envSpecs,
      List<ContainerVolumeMount> volumeMounts) {
    return List.of(
        new JSONPatchRecord(
            "add", String.format("/spec/containers/%d/volumeMounts", containerIndex), volumeMounts),
        new JSONPatchRecord(
            "add", String.format("/spec/containers/%d/env", containerIndex), envSpecs));
  }

  private APIGatewayV2HTTPResponse handlePodWithRole(AdmissionReview review, String roleArn) {
    log.info("AWS Role ARN: {}", roleArn);
    String podName = review.request().name();
    String podNamespace = review.request().namespace();
    AwsConfigFilesProvider.AwsConfigFiles files =
        configFilesProvider.getConfigFiles(roleArn, region, podName + "-" + podNamespace);
    Map<String, byte[]> secretEntries =
        Map.of(
            "config", files.config().getBytes(),
            "credentials", files.credentials().getBytes());
    String secretName = podName + "-aws-credentials";
    kubernetesSecretsClient.createSecret(secretName, podNamespace, secretEntries);
    log.info("Secret {} created", secretName);
    int containers = review.request().object().spec().containers().size();
    ContainerEnvSpec credentialsEnvSpec =
        new ContainerEnvSpec(AWS_SHARED_CREDENTIALS_FILE, "/opt/aws/credentials");
    ContainerEnvSpec configEnvSpec = new ContainerEnvSpec(AWS_CONFIG_FILE, "/opt/aws/config");
    List<ContainerEnvSpec> envSpecs = List.of(credentialsEnvSpec, configEnvSpec);
    List<ContainerVolumeMount> volumeMounts =
        List.of(new ContainerVolumeMount(VOLUME_NAME, true, "/opt/aws"));
    List<JSONPatchRecord> records =
        IntStream.range(0, containers)
            .mapToObj(idx -> containerUpdateRecords(idx, envSpecs, volumeMounts))
            .flatMap(List::stream)
            .toList();
    PodVolumeSpec volumeSpec = PodVolumeSpec.secret(VOLUME_NAME, secretName);
    List<JSONPatchRecord> volumeRecords =
        List.of(new JSONPatchRecord("add", "/spec/volumes", List.of(volumeSpec)));
    String patchJson =
        gson.toJson(Stream.concat(records.stream(), volumeRecords.stream()).toList());
    log.info("Patch json: {}", patchJson);
    String patch = Base64.getEncoder().encodeToString(patchJson.getBytes());
    AdmissionReview responseReview =
        AdmissionReview.response(
            AdmissionReview.Response.builder()
                .uid(review.request().uid())
                .allowed(true)
                .patchType(PATCH_TYPE)
                .patch(patch)
                .build());
    return success(responseReview);
  }

  private APIGatewayV2HTTPResponse handlePods(AdmissionReview review) {
    return Optional.ofNullable(review.request().object().metadata().annotations())
        .flatMap(annotations -> Optional.ofNullable(annotations.get(AWS_ROLE_ARN)))
        .map(roleArn -> handlePodWithRole(review, roleArn))
        .orElse(success(pass(review)));
  }

  @Override
  public APIGatewayV2HTTPResponse handleRequest(APIGatewayV2HTTPEvent input, Context context) {
    String tokenParam = System.getenv(TOKEN_PARAM);
    this.region = System.getenv(REGION_PARAM);
    setToken(tokenParam);
    setKubernetesSecretsClient();
    setConfigFilesProvider();
    Optional<String> authorization =
        Optional.ofNullable(input.getHeaders().get(AUTHORIZATION))
            .or(() -> Optional.ofNullable(input.getHeaders().get(AUTHORIZATION.toLowerCase())));
    if (authorization.isEmpty()) {
      log.error("Authorization header not found");
      return UNAUTHORIZED_RESPONSE;
    } else {
      Matcher matcher = BEARER_PATTERN.matcher(authorization.get());
      if (!matcher.matches() && !matcher.group(1).equals(this.token)) {
        log.error("Token did not match");
        return UNAUTHORIZED_RESPONSE;
      }
    }
    AdmissionReview review = gson.fromJson(input.getBody(), AdmissionReview.class);
    log.info("Received AdmissionReview: {}", review);
    return handlePods(review);
  }
}
