variable "lambda_subnet_ids" {
  description = "Subnet IDs for attaching Lambdas to a VPC (for Redis access). Leave empty to disable VPC attachment."
  type        = list(string)
  default     = []
}

variable "lambda_security_group_ids" {
  description = "Security group IDs for Lambdas attached to a VPC."
  type        = list(string)
  default     = []
}

