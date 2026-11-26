# =============================================================================
# 36-cloudtrail : who called which AWS API? (audit trail)
# =============================================================================
#
#   Every AWS API call (console, CLI, SDK, Terraform, and PODS using Pod Identity/IRSA credentials) is recorded: eks:*, sts:AssumeRole,
#   iam:*, kms:Decrypt, s3 management events... -> S3 bucket (SSE-S3, log file validation) -> investigations and compliance.
#   Kubernetes API calls are NOT in CloudTrail: they are in the EKS control-plane audit log (06-eks log types -> CloudWatch).
#   Pod Identity credentials show up as an assumed-role session tagged with cluster/namespace/service account: you can see WHICH pod acted.
# COST: the first management-events trail per account is FREE; additional trails, data events and CloudTrail Lake cost. S3 storage is small.
# ACCOUNT NOTE: if the account already has an organisation trail, you may not need this; keep enable_cloudtrail=false then.
# DEPENDS ON: nothing. DESTRUCTIVE: force_destroy deletes the audit logs on destroy (lab only; production keeps them).


locals {
  trail_name = "${local.name}-trail"
}

# WHY:        CloudTrail records every API call (who/what/when): the audit trail for incidents and AccessDenied debugging.
# DEPENDS:    Used by the trail.
# GOES WRONG: Deleting the bucket loses the audit history.
resource "aws_s3_bucket" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket        = "${local.name}-cloudtrail-${local.account_id}-${var.region}"
  force_destroy = var.force_destroy
}

# WHY:        Audit logs must never be public.
# DEPENDS:    Depends on the bucket.
# GOES WRONG: Without it an ACL mistake could expose account activity.
resource "aws_s3_bucket_public_access_block" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket                  = aws_s3_bucket.trail[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# WHY:        Encrypts logs at rest.
# DEPENDS:    Depends on the bucket; log files use SSE-S3 so no KMS key policy is involved.
# GOES WRONG: Switching to a KMS key later requires a key policy that lets cloudtrail.amazonaws.com use it, or delivery fails.
resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# WHY:        Bounds storage cost while keeping audit history for the retention period.
# DEPENDS:    Depends on the bucket.
# GOES WRONG: Too short a retention breaks compliance requirements.
resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.log_expiration_days
    }
  }
}

# CloudTrail (a service) writes into our bucket, so the bucket policy must trust it: only for THIS trail (aws:SourceArn -> no confused deputy).
data "aws_iam_policy_document" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  statement {
    sid       = "AWSCloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail[0].arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:cloudtrail:${var.region}:${local.account_id}:trail/${local.trail_name}"]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail[0].arn}/AWSLogs/${local.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:cloudtrail:${var.region}:${local.account_id}:trail/${local.trail_name}"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.trail[0].arn, "${aws_s3_bucket.trail[0].arn}/*"]

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

# WHY:        Allows the CloudTrail service to check the ACL and write objects for this trail only.
# DEPENDS:    Depends on the bucket and the trail ARN.
# GOES WRONG: Missing/incorrect policy: trail creation fails with InsufficientS3BucketPolicyException.
resource "aws_s3_bucket_policy" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket     = aws_s3_bucket.trail[0].id
  policy     = data.aws_iam_policy_document.trail[0].json
  depends_on = [aws_s3_bucket_public_access_block.trail]
}

# WHY multi-region + log file validation: attackers use unused regions; validation (digest files) proves logs were not altered afterwards.
# include_global_service_events: IAM/STS/CloudFront events are global and are logged in us-east-1 through this flag.
resource "aws_cloudtrail" "this" {
  count = var.enable_cloudtrail ? 1 : 0

  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.trail[0].id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.trail]
}

