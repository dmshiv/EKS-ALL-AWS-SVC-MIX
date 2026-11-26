data "terraform_remote_state" "dep" {
  for_each = {
    kms          = "16-kms"
    pod_identity = "08-pod-identity"
  }

  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/${each.value}/terraform.tfstate"
    region = var.region
  }
}

locals {
  out          = { for k, v in data.terraform_remote_state.dep : k => v.outputs }
  data_key_arn = local.out.kms.data_key_arn
  worker_role  = local.out.pod_identity.role_names["worker"]
}
