# =============================================================================
# 39-config : is everything configured the way policy says? (configuration history)
# =============================================================================
#
#   AWS Config records the configuration of supported resources over time (EKS cluster, security groups, IAM, S3, RDS...) and evaluates rules.
#   Answers "what did this security group look like last Tuesday?" and "which buckets are not encrypted?". It is the data source Security
#   Hub's compliance checks (38-security-hub) read; they show real results once Config is recording (either apply order works).
# COST: billed per configuration item recorded ($0.003 each) + rule evaluations: can surprise you in busy accounts. LAB: enable briefly.
# ACCOUNT NOTE: only ONE recorder per account per region: apply fails if one exists (aws configservice describe-configuration-recorders).
# DESTRUCTIVE: force_destroy deletes recorded history on destroy.


# ---------------------------------------------------------------------------------------------
# AWS CONFIG
# ---------------------------------------------------------------------------------------------
resource "aws_s3_bucket" "config" {
  count = var.enable_config ? 1 : 0

  bucket        = "${local.name}-config-${local.account_id}-${var.region}"
  force_destroy = var.force_destroy
}

# WHY:        Configuration history must never be public.
# DEPENDS:    Depends on the Config bucket.
# GOES WRONG: Without it an ACL mistake could expose resource inventories.
resource "aws_s3_bucket_public_access_block" "config" {
  count = var.enable_config ? 1 : 0

  bucket                  = aws_s3_bucket.config[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# WHY:        Bounds history storage cost.
# DEPENDS:    Depends on the Config bucket.
# GOES WRONG: No lifecycle = indefinite growth.
resource "aws_s3_bucket_lifecycle_configuration" "config" {
  count = var.enable_config ? 1 : 0

  bucket = aws_s3_bucket.config[0].id

  rule {
    id     = "expire-old-snapshots"
    status = "Enabled"

    filter {}

    expiration {
      days = var.log_expiration_days
    }
  }
}

data "aws_iam_policy_document" "config_bucket" {
  count = var.enable_config ? 1 : 0

  statement {
    sid       = "AWSConfigBucketPermissionsCheck"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.config[0].arn]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "AWSConfigBucketDelivery"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config[0].arn}/AWSLogs/${local.account_id}/Config/*"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

# WHY:        Allows AWS Config to deliver snapshots and history to this bucket.
# DEPENDS:    Depends on the bucket and the account ID.
# GOES WRONG: Delivery channel creation fails with InsufficientDeliveryPolicyException when this is wrong.
resource "aws_s3_bucket_policy" "config" {
  count = var.enable_config ? 1 : 0

  bucket     = aws_s3_bucket.config[0].id
  policy     = data.aws_iam_policy_document.config_bucket[0].json
  depends_on = [aws_s3_bucket_public_access_block.config]
}

data "aws_iam_policy_document" "config_assume" {
  count = var.enable_config ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

# WHY:        AWS Config needs a role to read resource configurations in the account.
# DEPENDS:    Trusted by config.amazonaws.com; used by the recorder.
# GOES WRONG: Recorder fails to start with an access error if the trust is wrong.
resource "aws_iam_role" "config" {
  count = var.enable_config ? 1 : 0

  name               = "${local.name}-aws-config"
  assume_role_policy = data.aws_iam_policy_document.config_assume[0].json
}

# WHY:        AWS managed read-only policy for Config.
# DEPENDS:    Depends on the Config role.
# GOES WRONG: Missing policy = recorder starts but records nothing.
resource "aws_iam_role_policy_attachment" "config" {
  count = var.enable_config ? 1 : 0

  role       = aws_iam_role.config[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

# The recorder records configuration CHANGES of supported resources (EKS cluster, SGs, IAM, S3...) so you can answer
# "what did the security group look like last Tuesday?". It must be created, then given a delivery channel, THEN started.
resource "aws_config_configuration_recorder" "this" {
  count = var.enable_config ? 1 : 0

  name     = "${local.name}-recorder"
  role_arn = aws_iam_role.config[0].arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

# WHY:        Tells Config where to deliver history; the recorder cannot start without it.
# DEPENDS:    Depends on the bucket policy and the recorder.
# GOES WRONG: Created before the bucket policy -> InsufficientDeliveryPolicyException.
resource "aws_config_delivery_channel" "this" {
  count = var.enable_config ? 1 : 0

  name           = "${local.name}-channel"
  s3_bucket_name = aws_s3_bucket.config[0].id

  depends_on = [aws_config_configuration_recorder.this, aws_s3_bucket_policy.config]
}

# WHY:        Recorder exists but does nothing until it is explicitly enabled.
# DEPENDS:    Depends on the recorder and delivery channel.
# GOES WRONG: Recorder disabled = Config rules and Security Hub config controls report NO data.
resource "aws_config_configuration_recorder_status" "this" {
  count = var.enable_config ? 1 : 0

  name       = aws_config_configuration_recorder.this[0].name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}

