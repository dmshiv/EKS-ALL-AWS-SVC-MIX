data "terraform_remote_state" "dns" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/26-route53/terraform.tfstate"
    region = var.region
  }
}

locals {
  enabled     = data.terraform_remote_state.dns.outputs.dns_enabled
  domain_name = data.terraform_remote_state.dns.outputs.domain_name
  zone_id     = data.terraform_remote_state.dns.outputs.zone_id
  # CloudFront only accepts certificates from us-east-1: reuse the regional one when the stack already runs there.
  need_global_cert = local.enabled && var.region != "us-east-1"
}
