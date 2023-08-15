resource "aws_service_discovery_private_dns_namespace" "control-plane-namespace" {
  name = "plane.local"
  vpc  = var.vpc-id
}

resource "aws_service_discovery_service" "control-plane-nodes-service" {
  name = "nodes"
  force_destroy = true
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.control-plane-namespace.id
    routing_policy = "MULTIVALUE"
    dns_records {
      ttl  = 20
      type = "A"
    }
  }
}