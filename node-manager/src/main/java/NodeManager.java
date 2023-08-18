import java.util.Optional;
import lombok.extern.slf4j.Slf4j;
import software.amazon.awssdk.services.ec2.model.Instance;
import software.amazon.awssdk.services.ec2.model.InstanceStateName;

@Slf4j
public class NodeManager {
  private static final int LOCK_TTL_SECONDS = 20;
  private final ServiceDiscovery serviceDiscovery;
  private final AwsInstances instances;
  private final KubernetesClient kubernetesClient;
  private final DynamoDbLockService lockService;
  private final String serviceId;

  private NodeManager(
      ServiceDiscovery serviceDiscovery,
      AwsInstances awsInstances,
      KubernetesClient kubernetesClient,
      DynamoDbLockService lockService,
      String serviceId) {
    this.serviceDiscovery = serviceDiscovery;
    this.instances = awsInstances;
    this.kubernetesClient = kubernetesClient;
    this.lockService = lockService;
    this.serviceId = serviceId;
  }

  public static NodeManager manager(String serviceId, String lockTableName) {
    SsmParameters parameters = new SsmParameters();
    String kubeConfig = parameters.getKubeconfigParam();
    KubernetesClient kubernetesClient = KubernetesClient.kubernetesClient(kubeConfig);
    DynamoDbLockService dynamoDbLockService = new DynamoDbLockService(lockTableName);
    return new NodeManager(
        new ServiceDiscovery(),
        new AwsInstances(),
        kubernetesClient,
        dynamoDbLockService,
        serviceId);
  }

  public void checkService() {
    log.info("Checking service {}", serviceId);
    lockService.lock(LOCK_TTL_SECONDS);
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
    lockService.unlock();
  }
}
