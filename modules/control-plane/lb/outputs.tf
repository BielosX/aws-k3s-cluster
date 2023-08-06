output "target-group-arn" {
  value = aws_lb_target_group.control-plane-lb-target-group.arn
}

output "dns" {
  value = aws_lb.control-plane-lb.dns_name
}