import java.util.Map;

public record KubernetesMetaObject(
    Map<String, String> annotations, Map<String, String> labels, String name, String namespace) {}
