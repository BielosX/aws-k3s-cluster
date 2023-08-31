public record KubernetesPod(
    KubernetesMetaObject metadata, String apiVersion, String kind, PodSpec spec) {}
