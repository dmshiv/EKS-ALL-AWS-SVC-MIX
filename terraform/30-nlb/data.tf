data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/01-vpc/terraform.tfstate"
    region = var.region
  }
}

locals {
  azs                = data.terraform_remote_state.vpc.outputs.azs
  public_subnet_ids  = data.terraform_remote_state.vpc.outputs.public_subnet_ids
  private_subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids
}
