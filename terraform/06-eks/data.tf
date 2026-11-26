data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/01-vpc/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "iam" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/05-iam/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "kms" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/16-kms/terraform.tfstate"
    region = var.region
  }
}

locals {
  private_subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids
  cluster_role_arn   = data.terraform_remote_state.iam.outputs.cluster_role_arn
  cluster_role_name  = data.terraform_remote_state.iam.outputs.cluster_role_name
  eks_key_arn        = data.terraform_remote_state.kms.outputs.eks_secrets_key_arn
}
