data "terraform_remote_state" "kms" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/16-kms/terraform.tfstate"
    region = var.region
  }
}
