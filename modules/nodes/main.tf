data "aws_vpc" "vpc" {
  id = var.vpc-id
}

resource "aws_security_group" "security-group" {
  vpc_id = var.vpc-id
  name_prefix = "node-sg"
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 443
    to_port = 443
    protocol = "tcp"
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 80
    to_port = 80
    protocol = "tcp"
  }
}

resource "aws_dynamodb_table" "lock-table" {
  name = "node-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key = "lockID"
  attribute {
    name = "lockID"
    type = "S"
  }
  ttl {
    enabled = true
    attribute_name = "expirationTime"
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
  instance-managed-policies = [
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
  instance-type = "t4g.small"
  instance-policy = data.aws_iam_policy_document.policy.json
  max-size = 3
  min-size = 3
  security-group-ids = [aws_security_group.security-group.id, var.kubernetes-node-sg-id]
  subnet-ids = var.subnet-ids
  instance-name = "node"
  metadata-hop-limit = 1
  string-write-files = [
    {
      permissions = "777"
      destination = "/etc/cron.hourly/refresh-ecr-token.sh"
      content = templatefile("${path.module}/../refresh-ecr-token.sh", {
        lock_table = aws_dynamodb_table.lock-table.name
        lock_table_key = "node-ecr-token-refresh"
      })
    }
  ]
}