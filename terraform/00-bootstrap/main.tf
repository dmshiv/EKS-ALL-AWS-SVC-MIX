# =============================================================================
# 00-bootstrap : remote-state bucket + cost guardrail
# =============================================================================
#
# CHICKEN-AND-EGG
#   Every other folder stores state in S3. The bucket itself must exist first, so THIS folder is
#   applied once with local state (terraform.tfstate next to this file, git-ignored). Losing that
#   local file is harmless: the bucket can be re-imported with `terraform import`.
#
# STATE LAYOUT (one object per folder = small blast radius, parallel work, per-folder IAM possible)
#   s3://<bucket>/<environment>/01-vpc/terraform.tfstate
#   s3://<bucket>/<environment>/06-eks/terraform.tfstate  ...

data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"
}

# WHY:    Durable, versioned, encrypted home for every Terraform state file.
# WHAT:   One S3 bucket. The account id in the name keeps it globally unique without a random suffix,
#         so scripts can compute the name deterministically.
# DEPENDS ON: nothing.  USED BY: every other folder (backend + terraform_remote_state).
# WHAT COULD GO WRONG: deleting it destroys all state => prevent_destroy. Versioning (below) lets you
#         roll back a corrupted state file.
# COST: pennies per month.
resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

# State history: every apply writes a new version, so a bad apply/corruption is recoverable.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3 (AES256) rather than a KMS key: the KMS key would itself need state to exist.
# State contains secrets (e.g. generated passwords), so encryption at rest is mandatory.
# PRODUCTION: use a dedicated KMS CMK with a key policy limited to the CI role.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# State must never be public.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Old versions are only useful for a while; expiring them stops unbounded growth.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

# SECURITY: refuse any non-TLS access to the bucket.
data "aws_iam_policy_document" "state" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# WHY:        Deny any request that is not TLS so state (which can contain secrets) never crosses the network in clear text.
# DEPENDS:    Depends on the state bucket; every later folder reads and writes its state through this bucket.
# GOES WRONG: A too-strict policy locks YOU out of your own state: keep the deny narrow (insecure transport only) and never deny your admin principal.
resource "aws_s3_bucket_policy" "state" {
  bucket     = aws_s3_bucket.state.id
  policy     = data.aws_iam_policy_document.state.json
  depends_on = [aws_s3_bucket_public_access_block.state]
}

# WHY:    This project creates NAT gateways, load balancers, EKS, RDS... A forgotten lab costs real money.
# WHAT:   A monthly cost budget with e-mail alerts. AWS gives 2 budgets free.
# NOTE:   Budgets are not real-time (data lags up to ~8-24h). It is a safety net, not a kill switch.
resource "aws_budgets_budget" "monthly" {
  count = var.budget_email == "" ? 0 : 1

  name         = "${var.project}-${var.environment}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}
