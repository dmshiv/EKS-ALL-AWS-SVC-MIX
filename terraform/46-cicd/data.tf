data "terraform_remote_state" "dep" {
  for_each = {
    ecr = "04-ecr"
    eks = "06-eks"
  }

  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/${each.value}/terraform.tfstate"
    region = var.region
  }
}

locals {
  out     = { for k, v in data.terraform_remote_state.dep : k => v.outputs }
  enabled = var.github_repository != ""
}
