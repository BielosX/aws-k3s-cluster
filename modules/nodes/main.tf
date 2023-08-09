locals {
  kubernetes-port = 6443
}

data "aws_vpc" "vpc" {
  id = var.vpc-id
}

resource "aws_security_group" "security-group" {
  vpc_id = var.vpc-id
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 443
    to_port = 443
    protocol = "tcp"
  }
  egress {
    cidr_blocks = [data.aws_vpc.vpc.cidr_block]
    from_port = local.kubernetes-port
    to_port = local.kubernetes-port
    protocol = "tcp"
  }
  ingress {
    cidr_blocks = [data.aws_vpc.vpc.cidr_block]
    from_port = local.kubernetes-port
    to_port = local.kubernetes-port
    protocol = "tcp"
  }
}

data "aws_iam_policy_document" "policy" {
  statement {
    effect = "Allow"
    actions = ["ssm:GetParameter"]
    resources = ["*"]
  }
}

module "asg" {
  source = "../asg"
  ami = var.ami
  cloud-watch-config = {
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path = "/var/log/user-data.log"
              log_group_name = "/nodes/var/log/user-data.log"
              log_stream_name = "{instance_id}"
            }
          ]
        }
      }
    }
  }
  init-script = file("${path.module}/init.sh")
  instance-managed-policies = ["arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"]
  instance-type = "t4g.small"
  instance-policy = data.aws_iam_policy_document.policy.json
  max-size = 3
  min-size = 3
  security-group-ids = [aws_security_group.security-group.id]
  subnet-ids = var.subnet-ids
  instance-name = "node"
}