import java.time.Instant;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.SneakyThrows;
import lombok.extern.slf4j.Slf4j;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException;
import software.amazon.awssdk.services.dynamodb.model.DeleteItemRequest;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;

@Slf4j
@RequiredArgsConstructor
public class DynamoDbLockService {
  private static final String LOCK_ID = "node-manager";
  private static final String LOCK_ATTRIBUTE = "lockID";
  private static final String CONDITION_EXPRESSION =
      String.format("attribute_not_exists(%s)", LOCK_ATTRIBUTE);
  private final DynamoDbClient client = DynamoDbClient.create();
  private final String lockTable;

  private PutItemRequest createRequest(int ttlSeconds) {
    Instant timestamp = Instant.now();
    Instant expirationTime = timestamp.plusSeconds(ttlSeconds);
    return PutItemRequest.builder()
        .tableName(lockTable)
        .conditionExpression(CONDITION_EXPRESSION)
        .item(
            Map.of(
                LOCK_ATTRIBUTE,
                AttributeValue.fromS(LOCK_ID),
                "timestamp",
                AttributeValue.fromN(String.valueOf(timestamp.getEpochSecond())),
                "expirationTime",
                AttributeValue.fromN(String.valueOf(expirationTime.getEpochSecond()))))
        .build();
  }

  @SneakyThrows
  public void lock(int ttlSeconds) {
    boolean retry = true;
    while (retry) {
      try {
        log.info("Trying to acquire lock");
        client.putItem(createRequest(ttlSeconds));
        retry = false;
      } catch (ConditionalCheckFailedException e) {
        log.info("Lock already created by other node. Waiting");
        Thread.sleep(500);
      }
    }
  }

  public void unlock() {
    DeleteItemRequest request =
        DeleteItemRequest.builder()
            .tableName(lockTable)
            .key(Map.of(LOCK_ATTRIBUTE, AttributeValue.fromS(LOCK_ID)))
            .build();
    client.deleteItem(request);
  }
}
