import java.io.InputStream;
import java.util.Map;
import lombok.SneakyThrows;
import org.apache.commons.text.StringSubstitutor;
import software.amazon.awssdk.services.sts.StsClient;
import software.amazon.awssdk.services.sts.model.AssumeRoleRequest;
import software.amazon.awssdk.services.sts.model.AssumeRoleResponse;

public class AwsConfigFilesProvider {
  private static final int DURATION_SECONDS = 3600;
  private static final String AWS_CONFIG_TEMPLATE = "aws-config.template";
  private static final String AWS_CREDENTIALS_TEMPLATE = "aws-credentials.template";
  private final StsClient stsClient = StsClient.create();
  private final String awsConfigTemplate;
  private final String awsCredentialsTemplate;

  public record AwsConfigFiles(String config, String credentials) {}

  private AwsConfigFilesProvider(String awsConfigTemplate, String awsCredentialsTemplate) {
    this.awsConfigTemplate = awsConfigTemplate;
    this.awsCredentialsTemplate = awsCredentialsTemplate;
  }

  @SneakyThrows
  public static AwsConfigFilesProvider awsConfigFilesProvider() {
    ClassLoader loader = AwsConfigFilesProvider.class.getClassLoader();
    String awsConfigTemplate;
    String awsCredentialsTemplate;
    try (InputStream stream = loader.getResourceAsStream(AWS_CONFIG_TEMPLATE)) {
      assert stream != null;
      awsConfigTemplate = new String(stream.readAllBytes());
    }
    try (InputStream stream = loader.getResourceAsStream(AWS_CREDENTIALS_TEMPLATE)) {
      assert stream != null;
      awsCredentialsTemplate = new String(stream.readAllBytes());
    }
    return new AwsConfigFilesProvider(awsConfigTemplate, awsCredentialsTemplate);
  }

  public AwsConfigFiles getConfigFiles(String roleArn, String region, String sessionName) {
    AssumeRoleRequest assumeRoleRequest =
        AssumeRoleRequest.builder()
            .roleArn(roleArn)
            .roleSessionName(sessionName)
            .durationSeconds(DURATION_SECONDS)
            .build();
    AssumeRoleResponse response = stsClient.assumeRole(assumeRoleRequest);
    String accessKeyId = response.credentials().accessKeyId();
    String secretAccessKey = response.credentials().secretAccessKey();
    String sessionToken = response.credentials().sessionToken();
    StringSubstitutor configSubstitutor = new StringSubstitutor(Map.of("region", region));
    String awsConfig = configSubstitutor.replace(this.awsConfigTemplate);
    StringSubstitutor credentialsSubstitutor =
        new StringSubstitutor(
            Map.of(
                "access_key_id", accessKeyId,
                "secret_access_key", secretAccessKey,
                "session_token", sessionToken));
    String awsCredentials = credentialsSubstitutor.replace(this.awsCredentialsTemplate);
    return new AwsConfigFiles(awsConfig, awsCredentials);
  }
}
