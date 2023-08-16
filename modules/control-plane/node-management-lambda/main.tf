data "aws_iam_policy_document" "lambda-assume-role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["lambda.amazonaws.com"]
      type = "Service"
    }
  }
}

resource "aws_iam_role" "lambda-role" {
  assume_role_policy = data.aws_iam_policy_document.lambda-assume-role.json
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole",
    "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess",
    "arn:aws:iam::aws:policy/AWSCloudMapFullAccess"
  ]
}

module "bucket" {
  source = "../../private-bucket"
  name-prefix = "lambda-artifacts"
}

resource "aws_s3_object" "artifact" {
  bucket = module.bucket.bucket-name
  key = "lambda.jar"
  source = var.file-path
  etag = filemd5(var.file-path)
}

resource "aws_lambda_function" "function" {
  function_name = "node-management-lambda"
  handler = "Handler::handleRequest"
  runtime = "java17"
  timeout = 10
  memory_size = 1024
  s3_bucket = module.bucket.bucket-name
  s3_key = aws_s3_object.artifact.key
  source_code_hash = filebase64sha256(var.file-path)
  vpc_config {
    security_group_ids = [var.security-group-id]
    subnet_ids = var.subnet-ids
  }
  environment {
    variables = {
      SERVICE_ID = var.control-plane-service-id
    }
  }
  role = aws_iam_role.lambda-role.arn
}

resource "aws_cloudwatch_event_rule" "lambda-rule" {
  schedule_expression = "rate(1 minute)"
  is_enabled = true
}

resource "aws_cloudwatch_event_target" "lambda-target" {
  arn  = aws_lambda_function.function.arn
  rule = aws_cloudwatch_event_rule.lambda-rule.name
}

resource "aws_lambda_permission" "event-bridge-invoke-permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.function.function_name
  principal = "events.amazonaws.com"
}