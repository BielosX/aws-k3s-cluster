import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

public class Main {
  public static void main(String[] args) {
    String serviceId = System.getenv("SERVICE_ID");
    NodeManager manager = NodeManager.manager();
    ScheduledExecutorService executor = Executors.newSingleThreadScheduledExecutor();
    executor.scheduleAtFixedRate(() -> manager.checkService(serviceId), 0, 5, TimeUnit.SECONDS);
  }
}
