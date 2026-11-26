# =============================================================================
# 15-s3 : product image bucket
# =============================================================================
#
#   product-service Pod --(Pod Identity creds, s3:PutObject/GetObject)--> S3 bucket (SSE-KMS)
#      path: Pod -> node ENI -> private RT -> S3 GATEWAY ENDPOINT (02) -> S3   (never touches the NAT)
#
# S3 IS OBJECT STORAGE, NOT A FILESYSTEM: there are no directories, no POSIX permissions, no appends. Applications
# call HTTP APIs (PutObject/GetObject). Mounting S3 into a pod (Mountpoint CSI) is possible but is a special case.
#
# WHO MAY ACCESS? Two independent gates, both must allow:
#   1. IAM policy on the pod's role (08-pod-identity)  -> s3:GetObject/PutObject on THIS bucket only
#   2. KMS key policy/IAM -> kms:GenerateDataKey/Decrypt on the data key (SSE-KMS requires both!)
# Typical AccessDenied: the role has S3 rights but not KMS rights (or the other way round).

# WHY:    Stores product images. The name carries account+region so it is globally unique and predictable.
# COST:   $0.023/GB-month + requests. Versioning stores every overwrite (cost + recovery). Free tier applies.
resource "aws_s3_bucket" "images" {
  bucket        = "${local.name}-product-images-${local.account_id}-${var.region}"
  force_destroy = var.force_destroy
}

# Versioning: an accidental overwrite/delete is recoverable. Combine with the lifecycle rule below.
resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption at rest with our CMK. bucket_key_enabled reduces KMS API calls (and cost) up to ~99%.
resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.data_key_arn
    }
  }
}

# SECURITY: images are served through the API/presigned URLs; the bucket is never public.
resource "aws_s3_bucket_public_access_block" "images" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket owner enforced: ACLs are disabled, only policies matter (simpler to reason about).
resource "aws_s3_bucket_ownership_controls" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# WHY:        Controls cost: abort incomplete uploads and expire old non-current versions.
# DEPENDS:    Depends on the images bucket and versioning.
# GOES WRONG: Versioning without lifecycle grows storage forever.
resource "aws_s3_bucket_lifecycle_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    id     = "expire-noncurrent-and-clean-multipart"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.images]
}

# Bucket policy = resource-based gate: refuse plaintext HTTP and refuse uploads not encrypted with our key.
data "aws_iam_policy_document" "images" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.images.arn, "${aws_s3_bucket.images.arn}/*"]

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

  statement {
    sid       = "DenyUploadsWithWrongKmsKey"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.images.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [local.data_key_arn]
    }
  }
}

# WHY:        Bucket policy enforces TLS and restricts access to the product-service role; identity policy and bucket policy BOTH must allow.
# DEPENDS:    Depends on the bucket and the role ARN; used by product-service.
# GOES WRONG: Principal typo = AccessDenied that no IAM change fixes; this is the classic S3 failure we inject on purpose.
resource "aws_s3_bucket_policy" "images" {
  bucket     = aws_s3_bucket.images.id
  policy     = data.aws_iam_policy_document.images.json
  depends_on = [aws_s3_bucket_public_access_block.images]
}

# ---------------------------------------------------------------------------------------------
# WHO MAY USE THE BUCKET (identity policies attached to roles created in 08-pod-identity and 09-irsa)
# ---------------------------------------------------------------------------------------------
# WHY HERE: the folder that owns the bucket owns the answer to "who may touch it". Least privilege: product-service may only
# read/write objects under products/ and list the bucket; nothing else in the cluster has these rights.
# KMS: SSE-KMS needs kms:GenerateDataKey (write) and kms:Decrypt (read) on the key, constrained with kms:ViaService so the key
# can only be used THROUGH S3 by this role (not directly).
# GOES WRONG (the classic AccessDenied): S3 permissions present, KMS permissions missing (or the other way round).
data "aws_iam_policy_document" "product_service_s3" {
  statement {
    sid       = "ListImagesBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.images.arn]
  }

  statement {
    sid       = "ReadWriteProductImages"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.images.arn}/products/*"]
  }

  statement {
    sid       = "UseDataKeyViaS3"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [local.data_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.region}.amazonaws.com"]
    }
  }
}

# WHY:        Least-privilege identity policy: only this bucket/prefix and only the needed actions plus KMS use.
# DEPENDS:    Depends on the product-service role (08-pod-identity).
# GOES WRONG: Missing KMS permission on a KMS-encrypted bucket returns AccessDenied even though S3 actions are allowed.
resource "aws_iam_role_policy" "product_service_s3" {
  name   = "s3-product-images"
  role   = local.product_role_name
  policy = data.aws_iam_policy_document.product_service_s3.json
}

# IRSA demo role (09-irsa): may only LIST the bucket, which is enough to prove the web-identity flow without granting data access.
data "aws_iam_policy_document" "irsa_demo_s3" {
  statement {
    sid       = "ListProductImages"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.images.arn]
  }
}

# WHY:        Same access, but for the IRSA demo role so Pod Identity and IRSA can be compared side by side.
# DEPENDS:    Depends on the IRSA demo role (09-irsa).
# GOES WRONG: Trust policy sub claim mismatch gives AssumeRoleWithWebIdentity AccessDenied before this policy is even evaluated.
resource "aws_iam_role_policy" "irsa_demo_s3" {
  name   = "s3-list-images"
  role   = local.irsa_role_name
  policy = data.aws_iam_policy_document.irsa_demo_s3.json
}

# Config publication: the application learns the bucket name from Parameter Store (see 18-parameter-store), not from YAML.
resource "aws_ssm_parameter" "bucket" {
  name  = "${local.ssm_prefix}/s3/bucket"
  type  = "String"
  value = aws_s3_bucket.images.id
}
