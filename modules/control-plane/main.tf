locals {
  init-script = <<-EOM
  #!/bin/bash -xe
  exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
    echo "Install K3S"
  EOM
}

module "security-group" {
  source = "./security-group"
  vpc-id = var.vpc-id
}

module "lb" {
  source = "./lb"
  subnet-ids = var.subnet-ids
  vpc-id = var.vpc-id
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
  init-script = local.init-script
  instance-managed-policies = [
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]
  instance-type = "t4g.small"
  max-size = 3
  min-size = 3
  security-group-ids = [module.security-group.control-plane-sg-id]
  subnet-ids = var.subnet-ids
  target-group-arns = [module.lb.target-group-arn]
}

module "cloud-map" {
  source = "./cloud-map"
  vpc-id = var.vpc-id
  load-balancer-dns = module.lb.dns
}