# =============================================================================
# 35-container-insights : pod/node metrics and container logs in CloudWatch
# =============================================================================
#
#   Pods --stdout--> node /var/log/containers --Fluent Bit (add-on DaemonSet)--> /aws/containerinsights/<cluster>/application
#   kubelet/cAdvisor --> CloudWatch agent (add-on) --> ContainerInsights namespace (pod/node CPU, memory, network, restarts)
#
# WHAT IT GIVES YOU: per-pod/per-node/per-namespace CPU, memory, restarts and container logs without running Prometheus/Loki. EKS ADD-ON
# "amazon-cloudwatch-observability" installs the CloudWatch agent + Fluent Bit and the operator that manages them.
# IDENTITY: the agent writes to CloudWatch, so it needs permissions: a Pod Identity role with the managed CloudWatchAgentServerPolicy
# (no node-role permissions needed, so the blast radius is one ServiceAccount).
# COST (watch this one): enhanced observability bills per observation; log ingestion ~$0.50/GB; metrics per custom metric; a chatty cluster
# can cost more than its nodes. LAB: enable while testing, destroy this folder afterwards. PRODUCTION: tune log collection, set retention,
# consider Prometheus/Grafana (managed) for high-cardinality metrics.
# ALTERNATIVES: Amazon Managed Prometheus + Grafana, Datadog/New Relic, OpenTelemetry (ADOT) for traces to X-Ray.
# DEPENDS ON: 06-eks, nodes (10). DEPENDED ON BY: 34-cloudwatch dashboard widget (ContainerInsights metrics).

# Pre-create the log groups so we control retention (the add-on would create them with "never expire").
resource "aws_cloudwatch_log_group" "container_insights" {
  for_each = toset(["application", "performance", "dataplane", "host"])

  name              = "/aws/containerinsights/${local.cluster_name}/${each.key}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# WHY:        The observability add-on's agent publishes metrics and logs to CloudWatch.
# DEPENDS:    Trusted via Pod Identity; used by the amazon-cloudwatch-observability add-on.
# GOES WRONG: No dashboards appear and the agent logs AccessDenied.
resource "aws_iam_role" "cloudwatch_agent" {
  name               = "${local.name}-cloudwatch-agent"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

# WHY:        AWS managed CloudWatchAgentServerPolicy.
# DEPENDS:    Depends on the agent role.
# GOES WRONG: Missing policy = no Container Insights metrics.
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# WHY:        Installs CloudWatch agent + Fluent Bit as a managed add-on: Container Insights metrics and pod logs.
# DEPENDS:    Depends on the cluster, nodes and the agent role.
# GOES WRONG: COST: log ingestion and custom metrics bill per GB/metric; disable when finished.
resource "aws_eks_addon" "observability" {
  cluster_name                = local.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  pod_identity_association {
    role_arn        = aws_iam_role.cloudwatch_agent.arn
    service_account = "cloudwatch-agent"
  }

  depends_on = [aws_cloudwatch_log_group.container_insights, aws_iam_role_policy_attachment.cloudwatch_agent]
}
