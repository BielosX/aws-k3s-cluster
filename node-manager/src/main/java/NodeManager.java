import java.util.Optional;
import lombok.extern.slf4j.Slf4j;
import software.amazon.awssdk.services.ec2.model.Instance;
import software.amazon.awssdk.services.ec2.model.InstanceStateName;

@Slf4j
public class NodeManager {
  private final ServiceDiscovery serviceDiscovery;
  private final AwsInstances instances;
  private final KubernetesClient kubernetesClient;

  private NodeManager(
      ServiceDiscovery serviceDiscovery,
      AwsInstances awsInstances,
      KubernetesClient kubernetesClient) {
    this.serviceDiscovery = serviceDiscovery;
    this.instances = awsInstances;
    this.kubernetesClient = kubernetesClient;
  }

  public static NodeManager manager() {
    SsmParameters parameters = new SsmParameters();
    String kubeConfig = parameters.getKubeconfigParam();
    KubernetesClient kubernetesClient = KubernetesClient.kubernetesClient(kubeConfig);
    return new NodeManager(new ServiceDiscovery(), new AwsInstances(), kubernetesClient);
  }

  public void checkService(String serviceId) {
    log.info("Checking service {}", serviceId);
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
  }
}
