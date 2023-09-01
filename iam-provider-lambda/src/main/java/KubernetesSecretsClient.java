import io.kubernetes.client.openapi.ApiClient;
import io.kubernetes.client.openapi.apis.CoreV1Api;
import io.kubernetes.client.openapi.models.V1ObjectMeta;
import io.kubernetes.client.openapi.models.V1Secret;
import io.kubernetes.client.util.ClientBuilder;
import io.kubernetes.client.util.KubeConfig;
import java.io.StringReader;
import java.util.Map;
import lombok.SneakyThrows;

public class KubernetesSecretsClient {
  private final ApiClient client;

  private KubernetesSecretsClient(ApiClient apiClient) {
    this.client = apiClient;
  }

  @SneakyThrows
  public static KubernetesSecretsClient kubernetesSecretsClient(String config) {
    StringReader reader = new StringReader(config);
    ApiClient apiClient = ClientBuilder.kubeconfig(KubeConfig.loadKubeConfig(reader)).build();
    return new KubernetesSecretsClient(apiClient);
  }

  @SneakyThrows
  public void createSecret(String name, String namespace, Map<String, byte[]> values) {
    CoreV1Api api = new CoreV1Api(client);
    V1Secret secret = new V1Secret();
    secret.setImmutable(false);
    secret.setData(values);
    secret.setApiVersion("v1");
    secret.setKind("Secret");
    V1ObjectMeta metadata = new V1ObjectMeta();
    metadata.name(name);
    metadata.namespace(namespace);
    secret.setMetadata(metadata);
    api.createNamespacedSecret(namespace, secret, null, null, null, null);
  }
}
