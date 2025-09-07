locals {
  # Derive VPC ID from the first provided Lambda subnet, if any
  use_vpc          = length(var.lambda_subnet_ids) > 0 && length(var.lambda_security_group_ids) > 0
}

data "aws_subnet" "lambda_subnet0" {
  count = local.use_vpc ? 1 : 0
  id    = var.lambda_subnet_ids[0]
}

locals {
  lambda_vpc_id = local.use_vpc ? data.aws_subnet.lambda_subnet0[0].vpc_id : null
}

# Interface VPC endpoint for Secrets Manager
resource "aws_vpc_endpoint" "secretsmanager" {
  count               = local.use_vpc ? 1 : 0
  vpc_endpoint_type   = "Interface"
  vpc_id              = local.lambda_vpc_id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  subnet_ids          = var.lambda_subnet_ids
  security_group_ids  = var.lambda_security_group_ids
  private_dns_enabled = true
}

# Interface VPC endpoint for KMS (Secrets decryption path)
resource "aws_vpc_endpoint" "kms" {
  count               = local.use_vpc ? 1 : 0
  vpc_endpoint_type   = "Interface"
  vpc_id              = local.lambda_vpc_id
  service_name        = "com.amazonaws.${var.region}.kms"
  subnet_ids          = var.lambda_subnet_ids
  security_group_ids  = var.lambda_security_group_ids
  private_dns_enabled = true
}

# Interface VPC endpoint for CloudWatch Logs (for reliable logging)
resource "aws_vpc_endpoint" "logs" {
  count               = local.use_vpc ? 1 : 0
  vpc_endpoint_type   = "Interface"
  vpc_id              = local.lambda_vpc_id
  service_name        = "com.amazonaws.${var.region}.logs"
  subnet_ids          = var.lambda_subnet_ids
  security_group_ids  = var.lambda_security_group_ids
  private_dns_enabled = true
}

