resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name_prefix}-http-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_headers = ["content-type"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_origins = ["*"]
    max_age       = 600
  }
  tags = local.tags
}

resource "aws_apigatewayv2_integration" "feed" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.feed.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "feed" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /v1/feed"
  target    = "integrations/${aws_apigatewayv2_integration.feed.id}"
}

resource "aws_lambda_permission" "apigw_feed" {
  statement_id  = "AllowAPIGatewayInvokeFeed"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.feed.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "events" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.events.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "events" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /v1/events"
  target    = "integrations/${aws_apigatewayv2_integration.events.id}"
}

resource "aws_lambda_permission" "apigw_events" {
  statement_id  = "AllowAPIGatewayInvokeEvents"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.events.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
  tags        = local.tags
}

output "api_base_url" { value = aws_apigatewayv2_api.http.api_endpoint }

