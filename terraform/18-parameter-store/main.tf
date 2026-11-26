# =============================================================================
# 18-parameter-store : the application's configuration contract
# =============================================================================
#
#   Each infrastructure folder PUBLISHES its endpoints:   15-s3 -> /cloudcart/<env>/s3/bucket
#                                                         19-rds -> /cloudcart/<env>/rds/host ... 21 redis, 22 sqs, 24 events, 20 dynamodb
#   This folder defines the shared prefix, shared app settings, and WHO MAY READ the prefix.
#   Pod (Pod Identity creds) --ssm:GetParametersByPath--> reads everything under /cloudcart/<env>/ at startup
#
# WHY: Kubernetes manifests and container images then contain NO environment-specific values. The same image and the same Helm chart run
# in lab/stage/prod; only the SSM prefix differs. When RDS is recreated and gets a new hostname, you re-apply Terraform and restart
# pods: no YAML edits, no image rebuild.
#
# WHICH STORE FOR WHAT: see 17-secrets-manager. Parameter Store = configuration (free standard tier, versioned, hierarchical).
# SecureString (KMS-encrypted) exists for secret-ish values that do not need rotation; we deliberately use Secrets Manager for real
# secrets and show a SecureString only in USER_GUIDE test 18.3.
#
# COST: standard String parameters are free (10,000 per account). Advanced tier and API throughput above the free limit cost a little.
# DEPENDS ON: 08-pod-identity (roles to grant).  GOES WRONG: AccessDeniedException on GetParametersByPath = the role is scoped to the
# wrong path. The action needs BOTH the prefix ARN and its children (parameter/path and parameter/path/*).

# WHY:        Non-secret configuration (table names, queue URLs, endpoints) lives in Parameter Store under /cloudcart/<env>/, outputs of Terraform become inputs of the app.
# DEPENDS:    Written here and by later folders; read by scripts/deploy-app.sh.
# GOES WRONG: Missing parameter = deploy script fails with ParameterNotFound: apply the producing folder first.
resource "aws_ssm_parameter" "app" {
  for_each = var.app_parameters

  name  = "${local.ssm_prefix}/${each.key}"
  type  = "String"
  value = each.value
}

data "aws_iam_policy_document" "read_config" {
  statement {
    sid     = "ReadOwnConfigFromParameterStore"
    actions = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [
      local.ssm_prefix_arn,
      "${local.ssm_prefix_arn}/*",
    ]
  }
}

# Every AWS-facing workload may READ (never write) the config prefix.
resource "aws_iam_role_policy" "read_config" {
  for_each = local.role_names

  name   = "read-ssm-config"
  role   = each.value
  policy = data.aws_iam_policy_document.read_config.json
}
