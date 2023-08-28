import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPResponse;
import com.google.gson.Gson;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import lombok.extern.slf4j.Slf4j;
import software.amazon.awssdk.services.ssm.SsmClient;
import software.amazon.awssdk.services.ssm.model.GetParameterRequest;
import software.amazon.awssdk.services.ssm.model.GetParameterResponse;

@Slf4j
public class Handler implements RequestHandler<APIGatewayV2HTTPEvent, APIGatewayV2HTTPResponse> {
  private static final APIGatewayV2HTTPResponse UNAUTHORIZED_RESPONSE =
      APIGatewayV2HTTPResponse.builder().withStatusCode(403).build();
  private static final Pattern BEARER_PATTERN = Pattern.compile("Bearer\\s+(\\w+)");
  private static final String AUTHORIZATION = "Authorization";
  private static final String TOKEN_PARAM = "TOKEN_PARAM";
  private final Gson gson = new Gson();
  private final SsmClient ssmClient = SsmClient.create();

  private String token;

  private void setToken(String paramName) {
    if (token == null) {
      GetParameterRequest request =
          GetParameterRequest.builder().name(paramName).withDecryption(true).build();
      GetParameterResponse response = ssmClient.getParameter(request);
      this.token = response.parameter().value();
    }
  }

  @Override
  public APIGatewayV2HTTPResponse handleRequest(APIGatewayV2HTTPEvent input, Context context) {
    String tokenParam = System.getenv(TOKEN_PARAM);
    setToken(tokenParam);
    Optional<String> authorization =
        Optional.ofNullable(input.getHeaders().get(AUTHORIZATION))
            .or(() -> Optional.ofNullable(input.getHeaders().get(AUTHORIZATION.toLowerCase())));
    if (authorization.isEmpty()) {
      log.error("Authorization header not found");
      return UNAUTHORIZED_RESPONSE;
    } else {
      Matcher matcher = BEARER_PATTERN.matcher(authorization.get());
      if (!matcher.matches() && !matcher.group(1).equals(this.token)) {
        log.error("Token did not match");
        return UNAUTHORIZED_RESPONSE;
      }
    }
    AdmissionReview review = gson.fromJson(input.getBody(), AdmissionReview.class);
    log.info("Received AdmissionReview: {}", review);
    AdmissionReview reviewResponse =
        AdmissionReview.response(
            AdmissionReview.Response.builder().allowed(true).uid(review.request().uid()).build());
    return APIGatewayV2HTTPResponse.builder()
        .withStatusCode(200)
        .withBody(gson.toJson(reviewResponse))
        .build();
  }
}
