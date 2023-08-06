locals {
  cw-config-content = base64encode(jsonencode(var.cloud-watch-config))
  cw-agent-dir = "/opt/aws/amazon-cloudwatch-agent"
  cw-agent-conf-file = "${local.cw-agent-dir}/etc/amazon-cloudwatch-agent.json"
  user-data = <<-EOT
  Content-Type: multipart/mixed; boundary="//"
  MIME-Version: 1.0

  --//
  Content-Type: text/cloud-config; charset="us-ascii"
  MIME-Version: 1.0
  Content-Transfer-Encoding: 7bit
  Content-Disposition: attachment; filename="cloud-config.txt"

  write_files:
    - encoding: b64
      path: ${local.cw-agent-conf-file}
      permissions: 444
      content: ${local.cw-config-content}
  packages:
    - amazon-cloudwatch-agent
    - jq
  runcmd:
    - ${local.cw-agent-dir}/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:${local.cw-agent-conf-file}

  --//
  Content-Type: text/x-shellscript; charset="us-ascii"
  MIME-Version: 1.0
  Content-Transfer-Encoding: 7bit
  Content-Disposition: attachment; filename="userdata.txt"

  ${var.init-script}
  --//--
  EOT
}

data "aws_iam_policy_document" "instance-assume-role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance-role" {
  assume_role_policy = data.aws_iam_policy_document.instance-assume-role.json
  dynamic "inline_policy" {
    for_each = var.instance-policy == "" ? [] : [1]
    content {
      name = "instance-policy"
      policy = var.instance-policy
    }
  }
  managed_policy_arns = var.instance-managed-policies
}

resource "aws_iam_instance_profile" "instance-profile" {
  role = aws_iam_role.instance-role.id
}

resource "aws_launch_template" "template" {
  image_id = var.ami
  instance_type = var.instance-type
  user_data = base64encode(local.user-data)
  vpc_security_group_ids = var.security-group-ids
  metadata_options {
    instance_metadata_tags = "enabled"
    http_endpoint = "enabled"
  }
  iam_instance_profile {
    arn = aws_iam_instance_profile.instance-profile.arn
  }
}

resource "aws_autoscaling_group" "asg" {
  max_size = var.min-size
  min_size = var.max-size
  vpc_zone_identifier = var.subnet-ids
  target_group_arns = var.target-group-arns
  dynamic "tag" {
    for_each = var.instance-name == "" ? [] : [1]
    content {
      key = "Name"
      value = var.instance-name
      propagate_at_launch = true
    }
  }
  launch_template {
    id = aws_launch_template.template.id
    version = aws_launch_template.template.latest_version
  }
}