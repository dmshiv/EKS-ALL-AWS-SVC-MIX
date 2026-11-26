# =============================================================================
# 37-guardduty : is something malicious happening? (threat detection)
# =============================================================================
#
#   GuardDuty analyses CloudTrail, VPC flow/DNS logs and the EKS AUDIT LOG with threat intelligence + ML, and raises findings, e.g.
#   "anonymous user granted access", "privileged container launched", "API called from a known-malicious IP", "credentials used from an
#   unusual location". RUNTIME MONITORING (optional) adds an agent per node that sees process/file/network behaviour inside containers.
# WHAT IT DOES NOT DO: it does not block anything (detective, not preventive) and it needs someone to triage findings.
# COST: usage-based (per GB of logs and per audit-log volume); 30-day free trial. Runtime monitoring bills per vCPU-hour of monitored nodes.
# ACCOUNT NOTE: only ONE detector per account per region: apply fails if one exists (aws guardduty list-detectors).


# ---------------------------------------------------------------------------------------------
# GUARDDUTY
# ---------------------------------------------------------------------------------------------
# EKS_AUDIT_LOGS: GuardDuty reads the cluster's audit stream (no agent, no setup in the cluster) and flags e.g. anonymous access,
#   privileged pod creation, known-malicious IP calling the API, exec into a pod.
# RUNTIME_MONITORING (optional): a security agent per node sees process/file/network behaviour inside containers (cryptominers, reverse shells).
resource "aws_guardduty_detector" "this" {
  count = var.enable_guardduty ? 1 : 0

  enable = true
}

# WHY:        Turns on EKS audit-log analysis without any agent.
# DEPENDS:    Depends on the detector.
# GOES WRONG: Feature name typos fail the plan; the feature bills by audit-log volume.
resource "aws_guardduty_detector_feature" "eks_audit" {
  count = var.enable_guardduty ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "EKS_AUDIT_LOGS"
  status      = "ENABLED"
}

# WHY:        Optional runtime agent for process/file/network visibility inside containers.
# DEPENDS:    Depends on the detector; installs a managed add-on on nodes.
# GOES WRONG: Agent needs egress to GuardDuty endpoints; blocked egress leaves it unhealthy.
resource "aws_guardduty_detector_feature" "runtime" {
  count = var.enable_guardduty && var.enable_guardduty_runtime ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "RUNTIME_MONITORING"
  status      = "ENABLED"

  additional_configuration {
    name   = "EKS_ADDON_MANAGEMENT"
    status = "ENABLED"
  }
}

