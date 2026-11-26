locals {
  states = {
    kms         = "16-kms"
    eks         = "06-eks"
    dynamodb    = "20-dynamodb"
    rds         = "19-rds"
    elasticache = "21-elasticache"
    sqs         = "22-sqs"
    events      = "24-eventbridge"
    lambda      = "25-lambda"
  }
}

data "terraform_remote_state" "dep" {
  for_each = local.states

  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/${each.value}/terraform.tfstate"
    region = var.region
  }
}

locals {
  out          = { for k, v in data.terraform_remote_state.dep : k => v.outputs }
  cluster_name = local.out.eks.cluster_name
}
