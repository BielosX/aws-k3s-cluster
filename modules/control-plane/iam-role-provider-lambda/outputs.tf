output "stage-url" {
  value = aws_apigatewayv2_stage.default-stage.invoke_url
}

output "token-parameter" {
  value = aws_ssm_parameter.webhook-token.id
}

output "role-arn" {
  value = aws_iam_role.role.arn
}