resource "aws_security_group" "security-group" {
  vpc_id = var.vpc-id
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 443
    to_port = 443
    protocol = "tcp"
  }
}

data "aws_ami" "linux-2023-arm" {
  most_recent = true
  filter {
    name = "architecture"
    values = ["arm64"]
  }
  filter {
    name = "description"
    values = ["Amazon Linux 2023*"]
  }
}

module "asg" {
  source = "../asg"
  ami = data.aws_ami.linux-2023-arm.id
  cloud-watch-config = {
  }
  init-script = ""
  instance-managed-policies = [
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]
  instance-type = "t4g.small"
  max-size = 3
  min-size = 3
  security-group-ids = [aws_security_group.security-group.id]
  subnet-ids = var.subnet-ids
}