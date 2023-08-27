import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPResponse;
import com.google.gson.Gson;
import lombok.extern.slf4j.Slf4j;

@Slf4j
public class Handler implements RequestHandler<APIGatewayV2HTTPEvent, APIGatewayV2HTTPResponse> {
  private final Gson gson = new Gson();

  @Override
  public APIGatewayV2HTTPResponse handleRequest(APIGatewayV2HTTPEvent input, Context context) {
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
