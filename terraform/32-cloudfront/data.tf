data "terraform_remote_state" "dns" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/26-route53/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "acm" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/27-acm/terraform.tfstate"
    region = var.region
  }
}

locals {
  dns     = data.terraform_remote_state.dns.outputs
  acm     = data.terraform_remote_state.acm.outputs
  enabled = var.enable_cloudfront && local.dns.dns_enabled
}
