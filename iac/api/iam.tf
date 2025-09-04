data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service" identifiers = ["lambda.amazonaws.com"] }
  }
}

resource "aws_iam_role" "api_lambda" {
  name               = "${local.name_prefix}-api-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.api_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "videos_read" {
  statement {
    actions   = ["dynamodb:Scan", "dynamodb:Query", "dynamodb:GetItem"]
    resources = [aws_dynamodb_table.videos.arn, "${aws_dynamodb_table.videos.arn}/index/*"]
  }
}

resource "aws_iam_policy" "videos_read" {
  name   = "${local.name_prefix}-videos-read"
  policy = data.aws_iam_policy_document.videos_read.json
}

resource "aws_iam_role_policy_attachment" "videos_read" {
  role       = aws_iam_role.api_lambda.name
  policy_arn = aws_iam_policy.videos_read.arn
}

data "aws_iam_policy_document" "put_firehose" {
  statement {
    actions   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
    resources = [aws_kinesis_firehose_delivery_stream.events.arn]
  }
}

resource "aws_iam_policy" "put_firehose" {
  name   = "${local.name_prefix}-events-firehose"
  policy = data.aws_iam_policy_document.put_firehose.json
}

resource "aws_iam_role_policy_attachment" "events_firehose" {
  role       = aws_iam_role.api_lambda.name
  policy_arn = aws_iam_policy.put_firehose.arn
}
