variable "region" {
  type = string
}

variable "env" {
  type = string
}

variable "account_id" {
  type = string
}

variable "project" {
  type    = string
  default = "signal"
}

locals {
  name_prefix = "${var.project}-${var.env}"
  tags = {
    Project = var.project
    Env     = var.env
  }
}
