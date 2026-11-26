data "terraform_remote_state" "dep" {
  for_each = {
    vpc    = "01-vpc"
    ecr    = "04-ecr"
    eks    = "06-eks"
    pod    = "08-pod-identity"
    irsa   = "09-irsa"
    efs    = "14-efs"
    ssm    = "18-parameter-store"
    dns    = "26-route53"
    acm    = "27-acm"
    albl   = "29-alb"
    nlb    = "30-nlb"
    waf    = "33-waf"
    lambda = "25-lambda"
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
}
