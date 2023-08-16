import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import java.util.Optional;
import lombok.SneakyThrows;
import lombok.extern.slf4j.Slf4j;
import software.amazon.awssdk.services.ec2.model.Instance;
import software.amazon.awssdk.services.ec2.model.InstanceStateName;

@Slf4j
public class Handler implements RequestHandler<Handler.EventBridgeEvent, Void> {
  private final ServiceDiscovery serviceDiscovery = new ServiceDiscovery();
  private final AwsInstances instances = new AwsInstances();
  private final SsmParameters parameters = new SsmParameters();
  private KubernetesClient kubernetesClient;

  @SneakyThrows
  private void initKubernetesClient() {
    if (kubernetesClient != null) {
      log.info("Kubernetes Client already initialized");
      return;
    }
    String kubeconfig = parameters.getKubeconfigParam();
    kubernetesClient = KubernetesClient.kubernetesClient(kubeconfig);
  }

  @Override
  public Void handleRequest(EventBridgeEvent input, Context context) {
    initKubernetesClient();
    String serviceId = System.getenv("SERVICE_ID");
    log.info("Lambda triggered at {}", input.time());
    serviceDiscovery
        .listInstances(serviceId)
        .forEach(
            instanceRecord -> {
              String id = instanceRecord.id();
              Optional<Instance> instance = instances.describeInstance(id);
              if (instance.isEmpty()) {
                log.info("Instance {} not found", id);
                serviceDiscovery.deregisterInstance(serviceId, id);
                kubernetesClient.deleteNode(id);
              } else {
                Instance ec2Instance = instance.get();
                InstanceStateName state = ec2Instance.state().name();
                if (!(state.equals(InstanceStateName.RUNNING)
                    || state.equals(InstanceStateName.PENDING))) {
                  log.info("Instance {} is not PENDING nor RUNNING", id);
                  serviceDiscovery.deregisterInstance(serviceId, id);
                  kubernetesClient.deleteNode(id);
                } else {
                  log.info("Instance {} is HEALTHY", id);
                }
              }
            });
    return null;
  }

  record EventBridgeEvent(String time) {}
}
