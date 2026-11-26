data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/06-eks/terraform.tfstate"
    region = var.region
  }
}

locals {
  oidc_provider_arn = data.terraform_remote_state.eks.outputs.oidc_provider_arn
  oidc_issuer       = data.terraform_remote_state.eks.outputs.oidc_issuer
}
