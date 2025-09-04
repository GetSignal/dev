resource "aws_s3_bucket" "analytics" {
  bucket = "${var.project}-analytics-${var.env}-${var.account_id}"
  force_destroy = true
  tags = local.tags
}

resource "aws_s3_bucket_versioning" "analytics" {
  bucket = aws_s3_bucket.analytics.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "analytics" {
  bucket = aws_s3_bucket.analytics.id
  rule { apply_server_side_encryption_by_default { sse_algorithm = "AES256" } }
}

resource "aws_iam_role" "firehose_role" {
  name               = "${local.name_prefix}-firehose-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "firehose.amazonaws.com" },
      Action = "sts:AssumeRole",
      Condition = { StringEquals = { "sts:ExternalId" = var.account_id } }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "firehose_to_s3" {
  name = "${local.name_prefix}-firehose-s3-policy"
  role = aws_iam_role.firehose_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:AbortMultipartUpload","s3:GetBucketLocation","s3:GetObject","s3:ListBucket","s3:ListBucketMultipartUploads","s3:PutObject"],
        Resource = [aws_s3_bucket.analytics.arn, "${aws_s3_bucket.analytics.arn}/*"]
      },
      {
        Effect = "Allow",
        Action = ["logs:PutLogEvents"],
        Resource = "*"
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "events" {
  name        = "${local.name_prefix}-events"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose_role.arn
    bucket_arn         = aws_s3_bucket.analytics.arn
    buffering_interval = 60
    buffering_size     = 5
    compression_format = "GZIP"
    prefix             = "raw/!{timestamp:yyyy}/!{timestamp:MM}/!{timestamp:dd}/!{timestamp:HH}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/!{timestamp:yyyy}/!{timestamp:MM}/!{timestamp:dd}/!{timestamp:HH}/"
    cloudwatch_logging_options { enabled = true }
  }

  tags = local.tags
}

output "events_firehose_stream_name" { value = aws_kinesis_firehose_delivery_stream.events.name }
output "analytics_bucket_name"       { value = aws_s3_bucket.analytics.bucket }

