data "terraform_remote_state" "kms" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/16-kms/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "pod_identity" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/08-pod-identity/terraform.tfstate"
    region = var.region
  }
}

locals {
  data_key_arn = data.terraform_remote_state.kms.outputs.data_key_arn
  role_names   = data.terraform_remote_state.pod_identity.outputs.role_names
}
