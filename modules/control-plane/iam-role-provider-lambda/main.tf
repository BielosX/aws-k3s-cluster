data "aws_iam_policy_document" "assume-role-policy" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["lambda.amazonaws.com"]
      type = "Service"
    }
  }
}

resource "random_password" "password" {
  length = 32
  special = false
}

resource "aws_ssm_parameter" "webhook-token" {
  name = "/control-plane/webhook-token"
  type = "SecureString"
  value = random_password.password.result
}

data "aws_iam_policy_document" "lambda-policy" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "role" {
  name = "iam-provider-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.assume-role-policy.json
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  ]
  inline_policy {
    name = "lambda-inline-policy"
    policy = data.aws_iam_policy_document.lambda-policy.json
  }
}

data "aws_region" "current" {}

locals {
  region = data.aws_region.current.name
}

resource "aws_lambda_function" "lambda" {
  function_name = "iam-role-provider-lambda"
  role = aws_iam_role.role.arn
  runtime = "java17"
  timeout = 60
  memory_size = 1024
  handler = "Handler::handleRequest"
  filename = var.lambda-file-path
  source_code_hash = filebase64sha256(var.lambda-file-path)
  environment {
    variables = {
      TOKEN_PARAM = aws_ssm_parameter.webhook-token.id
      REGION = local.region
    }
  }
  vpc_config {
    security_group_ids = [var.security-group-id]
    subnet_ids = var.subnets
  }
}

locals {
  openapi-body = {
    openapi = "3.0.1"
    info = {
      title = "Email API"
      description = "Email API"
      version = "1.0"
    }
    paths = {
      "/" = {
        post = {
          operationId: "Modify K8S object"
          "x-amazon-apigateway-integration": {
            type: "AWS_PROXY"
            httpMethod: "POST"
            uri = aws_lambda_function.lambda.arn
            payloadFormatVersion = "2.0"
          }
        }
      }
    }
  }
}

resource "aws_apigatewayv2_api" "api" {
  name = "kubernetes-modify"
  protocol_type = "HTTP"
  body = jsonencode(local.openapi-body)
}

resource "aws_apigatewayv2_stage" "default-stage" {
  api_id = aws_apigatewayv2_api.api.id
  name = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "permission" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal = "apigateway.amazonaws.com"
}