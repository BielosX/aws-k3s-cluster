locals {
  kubernetes-port = 6443
  ha-etcd-from = 2379
  ha-etcd-to = 2380
}

data "aws_vpc" "vpc" {
  id = var.vpc-id
}

resource "aws_security_group" "control-plane-sg" {
  vpc_id = var.vpc-id
  name_prefix = "control-plane-sg"
}

resource "aws_security_group" "lb-sg" {
  vpc_id =  var.vpc-id
  name_prefix = "load-balancer-sg"
  ingress {
    cidr_blocks = [data.aws_vpc.vpc.cidr_block]
    from_port = local.kubernetes-port
    to_port = local.kubernetes-port
    protocol = "tcp"
  }
  egress {
    security_groups = [aws_security_group.control-plane-sg.id]
    from_port = local.kubernetes-port
    to_port = local.kubernetes-port
    protocol = "tcp"
  }
}

resource "aws_security_group_rule" "kubernetes-self-ingress" {
  security_group_id = aws_security_group.control-plane-sg.id
  from_port = local.kubernetes-port
  to_port = local.kubernetes-port
  protocol = "tcp"
  self = true
  type = "ingress"
}

resource "aws_security_group_rule" "kubernetes-self-egress" {
  security_group_id = aws_security_group.control-plane-sg.id
  from_port = local.kubernetes-port
  to_port = local.kubernetes-port
  protocol = "tcp"
  self = true
  type = "egress"
}

resource "aws_security_group_rule" "https-egress" {
  security_group_id = aws_security_group.control-plane-sg.id
  cidr_blocks = ["0.0.0.0/0"]
  from_port = 443
  to_port = 443
  protocol = "tcp"
  type = "egress"
}

resource "aws_security_group_rule" "load-balancer-ingress" {
  security_group_id = aws_security_group.control-plane-sg.id
  source_security_group_id = aws_security_group.lb-sg.id
  from_port = local.kubernetes-port
  to_port = local.kubernetes-port
  protocol = "tcp"
  type = "ingress"
}

resource "aws_security_group_rule" "etcd-ingress" {
  from_port = local.ha-etcd-from
  to_port = local.ha-etcd-to
  protocol = "tcp"
  security_group_id = aws_security_group.control-plane-sg.id
  self = true
  type = "ingress"
}

resource "aws_security_group_rule" "etcd-egress" {
  from_port = local.ha-etcd-from
  to_port = local.ha-etcd-to
  protocol = "tcp"
  security_group_id = aws_security_group.control-plane-sg.id
  self = true
  type = "egress"
}

resource "aws_security_group" "node-sg" {
  vpc_id = var.vpc-id
  name_prefix = "kubernetes-node-sg"
  egress {
    security_groups = [aws_security_group.lb-sg.id]
    from_port = local.kubernetes-port
    to_port = local.kubernetes-port
    protocol = "tcp"
  }
  // https://github.com/k3s-io/k3s/discussions/4488#discussioncomment-1719009
  egress {
    security_groups = [aws_security_group.control-plane-sg.id]
    from_port = local.kubernetes-port
    to_port = local.kubernetes-port
    protocol = "tcp"
  }
  ingress {
    security_groups = [aws_security_group.control-plane-sg.id]
    from_port = local.kubernetes-port
    to_port = local.kubernetes-port
    protocol = "tcp"
  }
}

resource "aws_security_group_rule" "control-plane-to-node" {
  security_group_id = aws_security_group.control-plane-sg.id
  source_security_group_id = aws_security_group.node-sg.id
  from_port = local.kubernetes-port
  to_port = local.kubernetes-port
  protocol = "tcp"
  type = "egress"
}

resource "aws_security_group_rule" "control-plane-from-node" {
  security_group_id = aws_security_group.control-plane-sg.id
  source_security_group_id = aws_security_group.node-sg.id
  from_port = local.kubernetes-port
  to_port = local.kubernetes-port
  protocol = "tcp"
  type = "ingress"
}
