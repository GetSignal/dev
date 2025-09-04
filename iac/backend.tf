terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  backend "s3" {
    # Fill after running iac/bootstrap
    bucket         = "signal-tf-state-mvp-dev"
    key            = "signal/iac/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "signal-tf-lock-mvp-dev"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}

