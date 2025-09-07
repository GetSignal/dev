variable "trending_redis_url" {
  description = "Redis connection URL (use rediss:// for TLS)"
  type        = string
  default     = ""
}

variable "trending_redis_auth_token" {
  description = "Redis auth token (if required)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "trending_redis_auth_secret_arn" {
  description = "Secrets Manager ARN holding the Redis auth token"
  type        = string
  default     = ""
}
