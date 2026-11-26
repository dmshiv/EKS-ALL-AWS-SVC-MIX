data "terraform_remote_state" "dep" {
  for_each = {
    vpc = "01-vpc"
    sg  = "03-security-groups"
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
  out                = { for k, v in data.terraform_remote_state.dep : k => v.outputs }
  cluster_name       = local.out.eks.cluster_name
  private_subnet_ids = local.out.vpc.private_subnet_ids
  data_key_arn       = local.out.kms.data_key_arn
  efs_sg_id          = local.out.sg.efs_security_group_id
}
