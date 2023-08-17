import software.amazon.awssdk.services.ssm.SsmClient;
import software.amazon.awssdk.services.ssm.model.GetParameterRequest;
import software.amazon.awssdk.services.ssm.model.GetParameterResponse;

public class SsmParameters {
  private static final String KUBECONFIG_PARAM = "/control-plane/kubeconfig";
  private final SsmClient client = SsmClient.create();

  public String getKubeconfigParam() {
    GetParameterRequest request =
        GetParameterRequest.builder().name(KUBECONFIG_PARAM).withDecryption(true).build();
    GetParameterResponse response = client.getParameter(request);
    return response.parameter().value();
  }
}
