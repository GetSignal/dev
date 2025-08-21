###############################
# CloudFront + S3 cache recipe
###############################

# 1) Response headers policy to add immutable caching for sprites/VTT at the edge (viewer response)
resource "aws_cloudfront_response_headers_policy" "immutable_long_cache" {
  name = "signal-immutable-long-cache"
  custom_headers_config {
    items {
      header = "Cache-Control"
      override = true
      value = "public, max-age=31536000, immutable"
    }
  }
}

# 2) Cache policy: honor origin Cache-Control; set long TTLs as a safety net
resource "aws_cloudfront_cache_policy" "immutable_cache" {
  name = "signal-immutable-cache"
  min_ttl = 0
  default_ttl = 31536000
  max_ttl = 31536000
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
  }
}

# 3) Origin Access Control (recommended over legacy OAI)
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "signal-oac"
  description                       = "OAC for Signal sprites/VTT"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 4) Distribution (sprite/VTT behavior)
resource "aws_cloudfront_distribution" "cdn" {
  enabled = true

  origin {
    domain_name = aws_s3_bucket.storyboards.bucket_regional_domain_name
    origin_id   = "s3-storyboards"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-storyboards"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = aws_cloudfront_cache_policy.immutable_cache.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.immutable_long_cache.id
    compress               = true
  }

  price_class = "PriceClass_100"
  restrictions { geo_restriction { restriction_type = "none" } }
  viewer_certificate { cloudfront_default_certificate = true }
}

# 5) S3 bucket for storyboard assets
resource "aws_s3_bucket" "storyboards" {
  bucket = var.storyboard_bucket
}

# 6) Example of setting cache-control on upload (use your ingest code/build system)
# aws s3 cp ./storyboard/ s3://$BUCKET/ --recursive --cache-control "public, max-age=31536000, immutable" --content-type image/jpeg
# aws s3 cp ./storyboard.vtt s3://$BUCKET/path/ --cache-control "public, max-age=31536000, immutable" --content-type text/vtt
