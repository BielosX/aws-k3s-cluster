output "control-plane-nodes-service-id" {
  value = aws_service_discovery_service.control-plane-nodes-service.id
}

output "control-plane-nodes-service-arn" {
  value = aws_service_discovery_service.control-plane-nodes-service.arn
}
