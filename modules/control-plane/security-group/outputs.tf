output "control-plane-sg-id" {
  value = aws_security_group.control-plane-sg.id
}

output "load-balancer-sg-id" {
  value = aws_security_group.lb-sg.id
}

output "node-sg-id" {
  value = aws_security_group.node-sg.id
}