import io.kubernetes.client.openapi.ApiClient;
import io.kubernetes.client.openapi.apis.CoreV1Api;
import io.kubernetes.client.openapi.models.V1Node;
import io.kubernetes.client.openapi.models.V1NodeList;
import io.kubernetes.client.util.ClientBuilder;
import io.kubernetes.client.util.KubeConfig;
import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.Objects;
import java.util.Optional;
import lombok.SneakyThrows;
import lombok.extern.slf4j.Slf4j;

@Slf4j
public class KubernetesClient {
  private final ApiClient client;

  private KubernetesClient(ApiClient client) {
    this.client = client;
  }

  @SneakyThrows
  public static KubernetesClient kubernetesClient(String kubeconfig) {
    InputStream stream = new ByteArrayInputStream(kubeconfig.getBytes());
    ApiClient client =
        ClientBuilder.kubeconfig(KubeConfig.loadKubeConfig(new InputStreamReader(stream))).build();
    return new KubernetesClient(client);
  }

  @SneakyThrows
  public void deleteNode(String instanceId) {
    CoreV1Api api = new CoreV1Api(client);
    V1NodeList nodes =
        api.listNode(
            null, null, null, null, "aws/instance-id=" + instanceId, null, null, null, null, false);
    Optional<V1Node> node = nodes.getItems().stream().findFirst();
    if (node.isPresent()) {
      String name = Objects.requireNonNull(node.get().getMetadata()).getName();
      api.deleteNode(name, null, null, null, null, null, null);
    } else {
      log.warn("Node with label aws/instance-id={} not found", instanceId);
    }
  }
}
