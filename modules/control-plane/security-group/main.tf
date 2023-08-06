locals {
  kubernetes-port = 6443
}

data "aws_vpc" "vpc" {
  id = var.vpc-id
}

resource "aws_security_group" "control-plane-sg" {
  vpc_id = var.vpc-id
  ingress {
    cidr_blocks = [data.aws_vpc.vpc.cidr_block]
    from_port = local.kubernetes-port
    to_port = local.kubernetes-port
    protocol = "tcp"
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 443
    to_port = 443
    protocol = "tcp"
  }
}