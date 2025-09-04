resource "aws_dynamodb_table" "videos" {
  name         = "${local.name_prefix}-videos"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "video_id"
  attribute { name = "video_id"  type = "S" }
  attribute { name = "owner_id"  type = "S" }
  attribute { name = "-created_at" type = "S" }
  attribute { name = "day_bucket" type = "S" }
  attribute { name = "-engagement_score" type = "N" }

  global_secondary_index {
    name            = "gsi1_owner_created"
    hash_key        = "owner_id"
    range_key       = "-created_at"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "gsi2_day_engagement"
    hash_key        = "day_bucket"
    range_key       = "-engagement_score"
    projection_type = "ALL"
  }

  tags = local.tags
}

output "videos_table_name" { value = aws_dynamodb_table.videos.name }

