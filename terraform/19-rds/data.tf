data "terraform_remote_state" "dep" {
  for_each = {
    vpc     = "01-vpc"
    sg      = "03-security-groups"
    secrets = "17-secrets-manager"
    kms     = "16-kms"
  }

  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/${each.value}/terraform.tfstate"
    region = var.region
  }
}

locals {
  out = { for k, v in data.terraform_remote_state.dep : k => v.outputs }
}
