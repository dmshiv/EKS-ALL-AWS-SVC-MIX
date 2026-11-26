data "terraform_remote_state" "dep" {
  for_each = {
    eks = "06-eks"
    kms = "16-kms"
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
  cluster_name = local.out.eks.cluster_name
  data_key_arn = local.out.kms.data_key_arn
}
