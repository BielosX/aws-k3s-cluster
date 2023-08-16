import java.util.Optional;
import software.amazon.awssdk.services.ec2.Ec2Client;
import software.amazon.awssdk.services.ec2.model.DescribeInstancesRequest;
import software.amazon.awssdk.services.ec2.model.DescribeInstancesResponse;
import software.amazon.awssdk.services.ec2.model.Instance;

public class AwsInstances {
  private final Ec2Client client = Ec2Client.create();

  public Optional<Instance> describeInstance(String instanceId) {
    DescribeInstancesRequest request =
        DescribeInstancesRequest.builder().instanceIds(instanceId).build();
    DescribeInstancesResponse response = client.describeInstances(request);
    return response.reservations().stream()
        .flatMap(reservation -> reservation.instances().stream())
        .findFirst();
  }
}
