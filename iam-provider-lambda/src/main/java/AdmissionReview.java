import lombok.Builder;

public record AdmissionReview(String apiVersion, String kind, Request request, Response response) {
  private static final String API_VERSION = "admission.k8s.io/v1";
  private static final String KIND = "AdmissionReview";

  public record Resource(String group, String version, String resource) {}

  public record Request(
      String uid,
      Resource resource,
      String name,
      String namespace,
      KubernetesOperation operation,
      KubernetesPod object) {}

  @Builder
  public record Response(String uid, boolean allowed, String patchType, String patch) {}

  public static AdmissionReview response(Response response) {
    return new AdmissionReview(API_VERSION, KIND, null, response);
  }
}
