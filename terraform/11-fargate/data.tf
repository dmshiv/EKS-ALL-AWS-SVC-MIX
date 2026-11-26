data "terraform_remote_state" "dep" {
  for_each = {
    vpc = "01-vpc"
    iam = "05-iam"
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
  out                = { for k, v in data.terraform_remote_state.dep : k => v.outputs }
  cluster_name       = local.out.eks.cluster_name
  fargate_role_arn   = local.out.iam.fargate_role_arn
  private_subnet_ids = local.out.vpc.private_subnet_ids
}
