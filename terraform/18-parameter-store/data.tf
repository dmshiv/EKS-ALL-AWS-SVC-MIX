data "terraform_remote_state" "pod_identity" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/08-pod-identity/terraform.tfstate"
    region = var.region
  }
}

locals {
  role_names     = data.terraform_remote_state.pod_identity.outputs.role_names
  ssm_prefix_arn = "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter${local.ssm_prefix}"
}
