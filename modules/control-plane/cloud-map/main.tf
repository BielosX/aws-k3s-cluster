resource "aws_service_discovery_private_dns_namespace" "control-plane-namespace" {
  name = "plane.local"
  vpc  = var.vpc-id
}

resource "aws_service_discovery_service" "lb-service" {
  name = "lb"
  force_destroy = true
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.control-plane-namespace.id
    routing_policy = "WEIGHTED"
    dns_records {
      ttl  = 20
      type = "A"
    }
  }
}

resource "aws_service_discovery_instance" "lb-instance" {
  instance_id = "network"
  service_id  = aws_service_discovery_service.lb-service.id
  attributes  = {
    AWS_ALIAS_DNS_NAME = var.load-balancer-dns
  }
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