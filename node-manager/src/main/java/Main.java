import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import lombok.SneakyThrows;

public class Main {
  @SneakyThrows
  public static void main(String[] args) {
    String serviceId = System.getenv("SERVICE_ID");
    String lockTableName = System.getenv("LOCK_TABLE");
    NodeManager manager = NodeManager.manager(serviceId, lockTableName);
    ScheduledExecutorService executor = Executors.newSingleThreadScheduledExecutor();
    ScheduledFuture<?> future =
        executor.scheduleAtFixedRate(manager::checkService, 0, 10, TimeUnit.SECONDS);
    future.get();
  }
}
