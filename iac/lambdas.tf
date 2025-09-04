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
    }
  }

  tags = local.tags
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

