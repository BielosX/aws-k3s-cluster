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

resource "aws_iam_role" "role" {
  assume_role_policy = data.aws_iam_policy_document.assume-role-policy.json
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  ]
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