data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/06-eks/terraform.tfstate"
    region = var.region
  }
}

locals {
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
}
