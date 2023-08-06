module "security-group" {
  source = "./security-group"
  vpc-id = var.vpc-id
}

module "lb" {
  source = "./lb"
  subnet-ids = var.subnet-ids
  vpc-id = var.vpc-id
}

module "cloud-map" {
  source = "./cloud-map"
  vpc-id = var.vpc-id
  load-balancer-dns = module.lb.dns
}

resource "aws_dynamodb_table" "lock-table" {
  name = "control-plane-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key = "lockID"
  attribute {
    name = "lockID"
    type = "S"
  }
}

data "aws_iam_policy_document" "instance-role-policy" {
  statement {
    effect = "Allow"
    actions = ["dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.lock-table.arn]
  }
  statement {
    effect = "Allow"
    actions = ["servicediscovery:RegisterInstance"]
    resources = [module.cloud-map.control-plane-nodes-service-arn]
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
              log_group_name = "/var/log/user-data.log"
              log_stream_name = "{instance_id}"
            }
          ]
        }
      }
    }
  }
  instance-name = "control-plane-node"
  init-script = templatefile("${path.module}/init.sh", {
    lock_table = aws_dynamodb_table.lock-table.name
    service_id = module.cloud-map.control-plane-nodes-service-id
  })
  instance-managed-policies = [
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]
  instance-type = "t4g.small"
  instance-policy = data.aws_iam_policy_document.instance-role-policy.json
  max-size = 3
  min-size = 3
  security-group-ids = [module.security-group.control-plane-sg-id]
  subnet-ids = var.subnet-ids
  target-group-arns = [module.lb.target-group-arn]
}