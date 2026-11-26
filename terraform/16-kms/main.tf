# =============================================================================
# 16-kms : customer-managed encryption keys
# =============================================================================
#
# EXECUTION ORDER NOTE (the one place where folder number != apply order):
#   Many earlier folders encrypt with these keys (04-ecr, 06-eks Secrets envelope encryption, 13-ebs, 14-efs, 15-s3), so this folder
#   is applied right after 03-security-groups. See EXECUTION_ORDER.md. scripts/tf.sh refuses to run a folder whose upstream state
#   is missing, so a wrong order fails fast and safely.
#
# Two keys, two blast radii:
#   eks-secrets : only the EKS control plane uses it (envelope-encrypts Kubernetes Secrets in etcd).
#   data        : application data at rest (S3, SQS, SNS, DynamoDB, RDS, ElastiCache, EBS, EFS).
#
# HOW KMS ACCESS WORKS (interview favourite): a principal can use a key only if the KEY POLICY allows it.
# The default "root account" statement below means "IAM policies in this account may grant access".
# Without that statement, IAM policies alone are useless for this key.
#
# COST: $1/month per key (prorated) + $0.03 per 10,000 requests. Deleting is NOT instant (waiting period).

data "aws_iam_policy_document" "key_base" {
  # Delegates authorization to IAM policies (so least-privilege lives on the roles that need the key).
  statement {
    sid       = "EnableIAMPolicies"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }
}

# Service principals that encrypt on behalf of the account:
#   sns  : SNS topic encrypted with this key and SNS -> SQS fan-out into encrypted queues
#   sqs  : SQS delivering into other encrypted resources
#   events : EventBridge rules targeting encrypted queues
#   cloudwatch : CloudWatch alarms publishing to the encrypted alerts topic
# The aws:SourceAccount condition prevents the "confused deputy" problem (another account's SNS using our key).
data "aws_iam_policy_document" "data_key" {
  source_policy_documents = [data.aws_iam_policy_document.key_base.json]

  statement {
    sid    = "AllowAwsServicesInThisAccount"
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt",
    ]
    resources = ["*"]

    principals {
      type = "Service"
      identifiers = [
        "sns.amazonaws.com",
        "sqs.amazonaws.com",
        "events.amazonaws.com",
        "cloudwatch.amazonaws.com",
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

# WHY:    Kubernetes Secrets are only base64 in etcd. Envelope encryption encrypts them with a data key
#         wrapped by THIS key, so reading etcd storage without kms:Decrypt is useless.
# USED BY: 06-eks (encryption_config). The EKS cluster role must be allowed to use it (granted in 05).
# GOES WRONG: if the key is disabled/deleted the API server can no longer decrypt Secrets => cluster is
#         effectively broken. Hence a deletion window and rotation.
resource "aws_kms_key" "eks_secrets" {
  description             = "${local.name} EKS envelope encryption of Kubernetes Secrets"
  enable_key_rotation     = true
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = data.aws_iam_policy_document.key_base.json

  tags = { Name = "${local.name}-eks-secrets" }
}

# WHY:        Aliases give humans and policies a stable name; the key id is never hard-coded.
# DEPENDS:    Depends on the EKS secrets key; used by 06-eks.
# GOES WRONG: Deleting an alias does not delete the key but breaks anything referencing the alias.
resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${local.name}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

# WHY:    One CMK for application data lets us audit (CloudTrail kms:Decrypt) and revoke access to
#         all CloudCart data from one place.
# USED BY: 15-s3, 20-dynamodb, 19-rds, 21-elasticache, 22-sqs, 23-sns, 13-ebs (EBS/EFS), workloads (17).
# TRADEOFF: a CMK per service gives tighter blast radius; one shared key is simpler/cheaper for a lab.
resource "aws_kms_key" "data" {
  description             = "${local.name} application data at rest"
  enable_key_rotation     = true
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = data.aws_iam_policy_document.data_key.json

  tags = { Name = "${local.name}-data" }
}

# WHY:        Stable name for the data CMK used by S3, RDS, EBS, EFS, SQS, SNS and Secrets Manager.
# DEPENDS:    Depends on the data key.
# GOES WRONG: Key scheduled for deletion = EVERYTHING encrypted with it becomes unreadable after the window.
resource "aws_kms_alias" "data" {
  name          = "alias/${local.name}-data"
  target_key_id = aws_kms_key.data.key_id
}
