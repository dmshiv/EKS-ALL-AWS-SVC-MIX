data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/01-vpc/terraform.tfstate"
    region = var.region
  }
}

locals {
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc_id
}
