locals {
  kubernetes-port = 6443
}

resource "aws_lb" "control-plane-lb" {
  internal = true
  load_balancer_type = "network"
  subnets = var.subnet-ids
  security_groups = var.security-group-ids
}

resource "aws_lb_listener" "control-plane-lb" {
  load_balancer_arn = aws_lb.control-plane-lb.arn
  protocol = "TCP"
  port = local.kubernetes-port
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.control-plane-lb-target-group.arn
  }
}

resource "aws_lb_target_group" "control-plane-lb-target-group" {
  port = local.kubernetes-port
  protocol = "TCP"
  vpc_id = var.vpc-id
}