module "security-group" {
  source = "./security-group"
  vpc-id = var.vpc-id
}

module "cloud-map" {
  source = "./cloud-map"
  vpc-id = var.vpc-id
}

resource "aws_dynamodb_table" "lock-table" {
  name = "control-plane-lock"
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

data "aws_iam_policy_document" "instance-role-policy" {
  statement {
    sid = "ManageLock"
    effect = "Allow"
    actions = ["dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.lock-table.arn]
  }
  statement {
    sid = "RegisterInstance"
    effect = "Allow"
    actions = ["servicediscovery:RegisterInstance"]
    resources = [module.cloud-map.control-plane-nodes-service-arn]
  }
  statement {
    sid = "ListInstances"
    effect = "Allow"
    actions = ["servicediscovery:ListInstances"]
    resources = ["*"]
  }
  statement {
    sid = "ManageSSMParams"
    effect = "Allow"
    actions = [
      "ssm:DeleteParameter",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:PutParameter"
    ]
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
              log_group_name = "/control-plane/var/log/user-data.log"
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
    kubernetes_pod_cidr = var.kubernetes-pod-cidr
    kubernetes_service_cidr = var.kubernetes-service-cidr
    node_manager_image = var.node-manager-image
  })
  instance-managed-policies = [
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ]
  instance-type = "t4g.small"
  instance-policy = data.aws_iam_policy_document.instance-role-policy.json
  max-size = 3
  min-size = 3
  security-group-ids = [module.security-group.control-plane-sg-id]
  subnet-ids = var.subnet-ids
  metadata-hop-limit = 2
  string-write-files = [
    {
      permissions = "777"
      destination = "/etc/cron.hourly/refresh-ecr-token.sh"
      content = templatefile("${path.module}/../refresh-ecr-token.sh", {
        lock_table = aws_dynamodb_table.lock-table.name
        lock_table_key = "control-plane-ecr-token-refresh"
      })
    }
  ]
}