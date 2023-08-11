data "aws_ami" "amazon-linux-2023" {
  most_recent = true
  owners = ["amazon"]
  filter {
    name = "architecture"
    values = ["arm64"]
  }
  filter {
    name = "description"
    values = ["Amazon Linux 2023*"]
  }
}

data "aws_iam_policy_document" "assume-role-policy" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_vpc" "vpc" {
  id = var.vpc-id
}

resource "aws_iam_role" "role" {
  assume_role_policy = data.aws_iam_policy_document.assume-role-policy.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
}

resource "aws_iam_instance_profile" "instance-profile" {
  role = aws_iam_role.role.id
}

resource "aws_security_group" "security-group" {
  vpc_id = var.vpc-id
  name_prefix = "bastion-host-sg"
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 443
    to_port = 443
    protocol = "tcp"
  }
  egress {
    cidr_blocks = [data.aws_vpc.vpc.cidr_block]
    from_port = 6443
    to_port = 6443
    protocol = "tcp"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "bastion-host" {
  ami = data.aws_ami.amazon-linux-2023.id
  instance_type = "t4g.nano"
  iam_instance_profile = aws_iam_instance_profile.instance-profile.id
  subnet_id = var.public-subnet-id
  vpc_security_group_ids = [aws_security_group.security-group.id]
  user_data = <<-EOT
  #!/bin/bash
  yum update
  yum -y install dnsutils
  cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
  [kubernetes]
  name=Kubernetes
  baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
  enabled=1
  gpgcheck=1
  gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
  EOF
  yum -y install kubectl
  yum -y install https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_arm64/amazon-ssm-agent.rpm
  systemctl enable amazon-ssm-agent
  systemctl start amazon-ssm-agent
  EOT
  tags = {
    Name = "bastion-host"
  }
}