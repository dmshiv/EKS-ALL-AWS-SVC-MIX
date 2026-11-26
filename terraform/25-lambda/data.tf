data "terraform_remote_state" "dep" {
  for_each = {
    kms    = "16-kms"
    sns    = "23-sns"
    events = "24-eventbridge"
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
  data_key_arn  = local.out.kms.data_key_arn
  sns_topic_arn = local.out.sns.topic_arn
}
