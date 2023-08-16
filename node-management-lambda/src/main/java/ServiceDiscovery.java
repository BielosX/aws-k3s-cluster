import java.util.List;
import software.amazon.awssdk.services.servicediscovery.ServiceDiscoveryClient;
import software.amazon.awssdk.services.servicediscovery.model.DeregisterInstanceRequest;
import software.amazon.awssdk.services.servicediscovery.model.InstanceSummary;
import software.amazon.awssdk.services.servicediscovery.model.ListInstancesRequest;
import software.amazon.awssdk.services.servicediscovery.model.ListInstancesResponse;

public class ServiceDiscovery {
  private final ServiceDiscoveryClient client = ServiceDiscoveryClient.create();

  public List<InstanceSummary> listInstances(String serviceId) {
    ListInstancesRequest request = ListInstancesRequest.builder().serviceId(serviceId).build();
    ListInstancesResponse response = client.listInstances(request);
    return response.instances();
  }

  public void deregisterInstance(String serviceId, String instanceId) {
    DeregisterInstanceRequest request =
        DeregisterInstanceRequest.builder().serviceId(serviceId).instanceId(instanceId).build();
    client.deregisterInstance(request);
  }
}
