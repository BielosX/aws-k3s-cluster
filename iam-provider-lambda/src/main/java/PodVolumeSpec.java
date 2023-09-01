public record PodVolumeSpec(String name, PodVolumeSecretSpec secret) {
  public static PodVolumeSpec secret(String name, String secretName) {
    return new PodVolumeSpec(name, new PodVolumeSecretSpec(secretName));
  }
}
