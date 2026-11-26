# =============================================================================
# 40-backup : AWS Backup (central, policy-driven backups) and the DR story
# =============================================================================
#
#   Backup plan (daily 05:00 UTC) --selects by ARN--> RDS, DynamoDB, EFS --> recovery points in the VAULT (KMS-encrypted)
#                                                                              |  optional copy_action
#                                                                              v
#                                                                  DR vault in another region
#
# WHAT IS BACKED UP WHERE (answer for the disaster-recovery interview question)
#   RDS         automated backups + PITR (19-rds) AND AWS Backup copies (cross-region, retention policy, audit)
#   DynamoDB    PITR (35 days, 20-dynamodb) AND AWS Backup
#   EFS         AWS Backup (also enabled directly in 13-ebs)
#   EBS (PVCs)  snapshot via VolumeSnapshot / tag-based AWS Backup selection (docs/disaster-recovery)
#   S3          VERSIONING (15-s3) + optional cross-region replication; AWS Backup supports S3 too
#   Kubernetes  NOT in any of the above. Cluster state = Git (Helm chart + Argo CD) + Terraform. The cluster is cattle, data is pets.
#   Terraform state  S3 versioning (00-bootstrap)
# RTO/RPO: PITR gives RPO of minutes for RDS/DynamoDB; daily AWS Backup alone = RPO up to 24h. Restoring RDS from a recovery point takes
#   tens of minutes (RTO). Multi-AZ gives automatic failover for AZ loss but NOT protection against deletes/corruption: backups do.
# COST: backup storage ~$0.05/GB-month (RDS/EFS warm), $0.10 DynamoDB; cross-region adds transfer. Restores are billed too.
# NOTE: Backup Vault LOCK (WORM compliance mode) is deliberately NOT enabled: after its grace period it makes recovery points
#   undeletable for the whole retention (irreversible for a lab).

# WHY:        A vault holds recovery points encrypted with the CMK and is the unit of access control for backups.
# DEPENDS:    Used by the backup plan.
# GOES WRONG: Destroying the vault with recovery points is blocked: that is a safeguard, not a bug.
resource "aws_backup_vault" "this" {
  name          = "${local.name}-vault"
  kms_key_arn   = local.out.kms.data_key_arn
  force_destroy = var.force_destroy_vault

  tags = { Name = "${local.name}-vault" }
}

# WHY:        Cross-region copies survive a regional outage: the DR piece of the design.
# DEPENDS:    Created through the DR provider alias; target of the plan's copy action.
# GOES WRONG: COST: cross-region storage + transfer; disabled unless DR is being exercised.
resource "aws_backup_vault" "dr" {
  count    = var.enable_cross_region_copy ? 1 : 0
  provider = aws.dr

  name          = "${local.name}-vault-dr"
  force_destroy = var.force_destroy_vault

  tags = { Name = "${local.name}-vault-dr" }
}

# WHY:        Defines WHEN, WHERE and HOW LONG backups are kept: RPO is the schedule, retention is the cost.
# DEPENDS:    Depends on the vaults; resources are attached by tag selection.
# GOES WRONG: A plan with no resource selection backs up nothing: verify with list-protected-resources.
resource "aws_backup_plan" "daily" {
  name = "${local.name}-daily"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 5 * * ? *)"
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = var.retention_days
    }

    dynamic "copy_action" {
      for_each = var.enable_cross_region_copy ? [1] : []

      content {
        destination_vault_arn = aws_backup_vault.dr[0].arn

        lifecycle {
          delete_after = var.retention_days
        }
      }
    }
  }
}

# The role AWS Backup assumes to read/snapshot the resources (and to restore them).
data "aws_iam_policy_document" "backup_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

# WHY:        AWS Backup acts through a service role to snapshot resources.
# DEPENDS:    Trusted by backup.amazonaws.com.
# GOES WRONG: Jobs fail with 'insufficient privileges' if the role lacks the service policy.
resource "aws_iam_role" "backup" {
  name               = "${local.name}-aws-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
}

# WHY:        AWS managed backup policy.
# DEPENDS:    Depends on the backup role.
# GOES WRONG: Restore jobs need the separate restore managed policy.
resource "aws_iam_role_policy_attachment" "backup" {
  for_each = toset([
    "service-role/AWSBackupServiceRolePolicyForBackup",
    "service-role/AWSBackupServiceRolePolicyForRestores",
  ])

  role       = aws_iam_role.backup.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value}"
}

# The role must also be allowed to use the vault's KMS key.
data "aws_iam_policy_document" "backup_kms" {
  statement {
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt", "kms:DescribeKey", "kms:CreateGrant"]
    resources = [local.out.kms.data_key_arn]
  }
}

# WHY:        Backing up encrypted resources requires KMS grants for the backup role.
# DEPENDS:    Depends on the backup role and the CMK.
# GOES WRONG: Backup of encrypted RDS/EBS fails with a KMS access error.
resource "aws_iam_role_policy" "backup_kms" {
  name   = "use-data-key"
  role   = aws_iam_role.backup.id
  policy = data.aws_iam_policy_document.backup_kms.json
}

# Selection by explicit ARN keeps the blast radius obvious. PRODUCTION: select by tag (Backup=daily) so new resources are covered automatically.
resource "aws_backup_selection" "data" {
  name         = "${local.name}-data"
  plan_id      = aws_backup_plan.daily.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [
    local.rds_arn,
    local.out.dynamodb.table_arn,
    local.efs_arn,
  ]

  depends_on = [aws_iam_role_policy_attachment.backup, aws_iam_role_policy.backup_kms]
}
