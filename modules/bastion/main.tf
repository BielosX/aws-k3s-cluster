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

resource "aws_iam_role" "role" {
  assume_role_policy = data.aws_iam_policy_document.assume-role-policy.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
}

resource "aws_iam_instance_profile" "instance-profile" {
  role = aws_iam_role.role.id
}

resource "aws_security_group" "security-group" {
  vpc_id = var.vpc-id
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 443
    to_port = 443
    protocol = "tcp"
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
  yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_arm64/amazon-ssm-agent.rpm
  systemctl enable amazon-ssm-agent
  systemctl start amazon-ssm-agent
  EOT
  tags = {
    Name = "bastion-host"
  }
}