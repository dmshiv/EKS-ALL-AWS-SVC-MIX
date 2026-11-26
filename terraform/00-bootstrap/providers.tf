# Credentials: none in code. The AWS CLI default chain is used (AWS_PROFILE / SSO / environment).
# default_tags put the cost-allocation tags on every taggable resource in this folder.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "CloudCart"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
      Layer       = "00-bootstrap"
    }
  }
}
