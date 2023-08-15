output "control-plane-sg-id" {
  value = aws_security_group.control-plane-sg.id
}

output "node-sg-id" {
  value = aws_security_group.node-sg.id
}