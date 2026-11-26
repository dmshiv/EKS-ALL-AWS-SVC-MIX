data "terraform_remote_state" "dep" {
  for_each = {
    vpc = "01-vpc"
    sg  = "03-security-groups"
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
  cluster_sg_id      = local.out.eks.cluster_security_group_id
  node_sg_id         = local.out.sg.node_security_group_id
  node_role_arn      = local.out.iam.node_role_arn
  private_subnet_ids = local.out.vpc.private_subnet_ids
}
