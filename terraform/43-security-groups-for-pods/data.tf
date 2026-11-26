data "terraform_remote_state" "dep" {
  for_each = {
    vpc = "01-vpc"
    sg  = "03-security-groups"
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
  out           = { for k, v in data.terraform_remote_state.dep : k => v.outputs }
  vpc_id        = local.out.vpc.vpc_id
  cluster_sg_id = local.out.eks.cluster_security_group_id
  rds_sg_id     = local.out.sg.rds_security_group_id
}
