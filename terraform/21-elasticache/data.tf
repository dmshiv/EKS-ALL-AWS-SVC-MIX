data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/01-vpc/terraform.tfstate"
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

data "terraform_remote_state" "sg" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/03-security-groups/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "secrets" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/17-secrets-manager/terraform.tfstate"
    region = var.region
  }
}
