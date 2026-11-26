data "terraform_remote_state" "dep" {
  for_each = {
    kms      = "16-kms"
    dynamodb = "20-dynamodb"
    rds      = "19-rds"
    storage  = "14-efs"
  }

  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/${each.value}/terraform.tfstate"
    region = var.region
  }
}

locals {
  out = { for k, v in data.terraform_remote_state.dep : k => v.outputs }

  rds_arn = "arn:${local.partition}:rds:${var.region}:${local.account_id}:db:${local.out.rds.db_identifier}"
  efs_arn = "arn:${local.partition}:elasticfilesystem:${var.region}:${local.account_id}:file-system/${local.out.storage.efs_file_system_id}"
}
