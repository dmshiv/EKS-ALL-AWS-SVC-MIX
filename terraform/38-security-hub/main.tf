# =============================================================================
# 38-security-hub : one place for all security findings and best-practice checks
# =============================================================================
#
#   Aggregates findings from GuardDuty, Config, Inspector, IAM Access Analyzer... and runs the AWS Foundational Security Best Practices checks
#   (e.g. "EKS.1 cluster endpoint should not be public", "S3 buckets should require SSL", "RDS should not be public").
#   EXPECT FINDINGS in this lab ON PURPOSE (public API endpoint, single NAT, deletion protection off): reading and triaging them is the exercise.
# COST: billed per security check and per ingested finding; the 30-day trial applies. Config-based controls need AWS Config recording (39-config); either apply order works.
# VALUE: central visibility and a compliance score; LIMITS: it does not fix anything and noisy defaults need tuning (suppression rules).


# ---------------------------------------------------------------------------------------------
# SECURITY HUB
# ---------------------------------------------------------------------------------------------
# Aggregates findings and runs the AWS Foundational Security Best Practices checks (e.g. "EKS.1 cluster endpoint should not be public",
# "RDS instances should not be public", "S3 buckets should enforce SSL"). Expect findings in this lab on purpose (public endpoint,
# single NAT, deletion protection off): reading them is part of the exercise.
resource "aws_securityhub_account" "this" {
  count = var.enable_securityhub ? 1 : 0

  enable_default_standards = false

  # Config-based controls report no data until 39-config is applied; either order works, findings fill in once Config is recording.
}

# WHY:        Enables the AWS Foundational Security Best Practices checks.
# DEPENDS:    Depends on Security Hub being enabled (and Config recording for config-based controls).
# GOES WRONG: Findings appear on purpose in this lab (public endpoint etc.); they are not errors.
resource "aws_securityhub_standards_subscription" "fsbp" {
  count = var.enable_securityhub ? 1 : 0

  standards_arn = "arn:${local.partition}:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.this]
}
