# ---------------------------------------------------------------------------------------------
# WHO MAY USE THE TABLE + CONFIG PUBLICATION
# ---------------------------------------------------------------------------------------------
# The folder that owns the table owns its access policy: ONLY product-service may read/write THIS table and its index.
# DynamoDB authentication is IAM only (no passwords). With a customer-managed KMS key, DynamoDB uses the key on behalf of the caller,
# so the pod needs NO kms permission here (unlike S3 and SQS).
# GOES WRONG: AccessDeniedException ... "not authorized to perform dynamodb:Query on resource .../index/category-index" =
# index access needs the /index/* resource ARN in addition to the table ARN.

data "terraform_remote_state" "pod_identity" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/08-pod-identity/terraform.tfstate"
    region = var.region
  }
}

data "aws_iam_policy_document" "product_service_dynamodb" {
  statement {
    sid = "CatalogTable"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]
    resources = [
      aws_dynamodb_table.products.arn,
      "${aws_dynamodb_table.products.arn}/index/*",
    ]
  }
}

# WHY:        Least privilege: only the actions the service uses, only on this table and its indexes.
# DEPENDS:    Depends on the product-service role and table ARN.
# GOES WRONG: AccessDeniedException naming the table ARN = scope mismatch; check you used the table ARN, not the name.
resource "aws_iam_role_policy" "product_service_dynamodb" {
  name   = "dynamodb-products"
  role   = data.terraform_remote_state.pod_identity.outputs.role_names["product-service"]
  policy = data.aws_iam_policy_document.product_service_dynamodb.json
}

# WHY:        Publishes the table name for the service config.
# DEPENDS:    Read by the deploy script/Helm values.
# GOES WRONG: Hard-coding the name in manifests breaks other environments.
resource "aws_ssm_parameter" "table_name" {
  name  = "${local.ssm_prefix}/dynamodb/table_name"
  type  = "String"
  value = aws_dynamodb_table.products.name
}
