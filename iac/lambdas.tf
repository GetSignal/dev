resource "aws_lambda_function" "feed" {
  function_name = "${local.name_prefix}-feed"
  role          = aws_iam_role.api_lambda.arn
  runtime       = "nodejs20.x"
  handler       = "index.handler"
  filename      = "${path.module}/../services/api/dist/feed.zip"
  source_code_hash = filebase64sha256("${path.module}/../services/api/dist/feed.zip")

  environment {
    variables = {
      VIDEOS_TABLE     = aws_dynamodb_table.videos.name
      EXPLORATION_MIN  = "0.10"
      EXPLORATION_MAX  = "0.20"
      FEED_LIMIT       = "20"
      FALLBACK_DAYS    = "3"
      TRENDING_REDIS_URL                = var.trending_redis_url
      TRENDING_REDIS_AUTH_TOKEN         = var.trending_redis_auth_token
      TRENDING_REDIS_AUTH_SECRET_ARN    = var.trending_redis_auth_secret_arn
    }
  }

  dynamic "vpc_config" {
    for_each = length(var.lambda_subnet_ids) > 0 && length(var.lambda_security_group_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.lambda_subnet_ids
      security_group_ids = var.lambda_security_group_ids
    }
  }

  timeout = 10

  tags = local.tags
}

resource "aws_lambda_function" "trending_writer" {
  function_name = "${local.name_prefix}-trending-writer"
  role          = aws_iam_role.api_lambda.arn
  runtime       = "nodejs20.x"
  handler       = "index.handler"
  filename      = "${path.module}/../services/api/dist/trending-writer.zip"
  source_code_hash = filebase64sha256("${path.module}/../services/api/dist/trending-writer.zip")

  environment {
    variables = {
      VIDEOS_TABLE = aws_dynamodb_table.videos.name
      FALLBACK_DAYS = "3"
      TRENDING_SET_KEY = "trending:v1"
      TRENDING_SIZE = "1000"
      TRENDING_REDIS_URL = var.trending_redis_url
      TRENDING_REDIS_AUTH_TOKEN = var.trending_redis_auth_token
      TRENDING_REDIS_AUTH_SECRET_ARN = var.trending_redis_auth_secret_arn
    }
  }

  tags = local.tags
}

resource "aws_cloudwatch_event_rule" "trending_schedule" {
  name                = "${local.name_prefix}-trending-writer-schedule"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "trending_target" {
  rule      = aws_cloudwatch_event_rule.trending_schedule.name
  target_id = "trending-writer"
  arn       = aws_lambda_function.trending_writer.arn
}

resource "aws_lambda_permission" "allow_events_trending" {
  statement_id  = "AllowExecutionFromCloudWatchEventsTrending"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trending_writer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.trending_schedule.arn
}

resource "aws_lambda_function" "events" {
  function_name = "${local.name_prefix}-events"
  role          = aws_iam_role.api_lambda.arn
  runtime       = "nodejs20.x"
  handler       = "index.handler"
  filename      = "${path.module}/../services/api/dist/events.zip"
  source_code_hash = filebase64sha256("${path.module}/../services/api/dist/events.zip")

  environment {
    variables = {
      FIREHOSE_STREAM                    = aws_kinesis_firehose_delivery_stream.events.name
      AWS_NODEJS_CONNECTION_REUSE_ENABLED = "1"
    }
  }
  tags = local.tags
}

resource "aws_lambda_function" "manifest" {
  function_name = "${local.name_prefix}-manifest"
  role          = aws_iam_role.api_lambda.arn
  runtime       = "nodejs20.x"
  handler       = "index.handler"
  filename      = "${path.module}/../services/api/dist/manifest.zip"
  source_code_hash = filebase64sha256("${path.module}/../services/api/dist/manifest.zip")
  tags = local.tags
}
