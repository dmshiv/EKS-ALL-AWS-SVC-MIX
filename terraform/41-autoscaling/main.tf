# =============================================================================
# 41-autoscaling : metrics for the HPA (+ optional Cluster Autoscaler comparison)
# =============================================================================
#
# THREE AUTOSCALERS, THREE LAYERS (do not mix them up)
#   HPA (Horizontal Pod Autoscaler)  : changes the NUMBER OF PODS from metrics (CPU/memory/custom). Needs metrics-server (this folder).
#                                      Manifests: kubernetes/autoscaling/*.yaml.
#   Karpenter (12 + kubernetes/karpenter) : changes the NUMBER/SHAPE OF NODES in response to UNSCHEDULABLE pods. Chooses instance types.
#   Cluster Autoscaler (optional here): changes the DESIRED SIZE of pre-defined Auto Scaling Groups when pods are unschedulable.
#
# THE SCALING CHAIN: load rises -> HPA adds pods -> pods Pending (no room) -> Karpenter (or CA) adds a node -> pods scheduled -> load falls
#   -> HPA removes pods -> nodes become empty/under-used -> consolidation (Karpenter) or scale-down (CA) removes nodes.
# KARPENTER vs CLUSTER AUTOSCALER
#   CA     : works through ASGs (one instance type family per group), reacts in minutes, bin-packs only within the group's shape, scale-down
#            is conservative; you manage many node groups.
#   Karpenter : no ASGs; calls EC2 Fleet directly, picks the cheapest fitting instance from the whole catalogue per batch of pending pods,
#            consolidates proactively, handles Spot interruption natively. Usually faster and cheaper; CA is mature and portable.
# COST: metrics-server runs on existing nodes. The autoscalers themselves are free; the NODES they add cost money.

# WHAT: the metrics.k8s.io API (CPU/memory per pod/node) used by `kubectl top` and the HPA. Without it an HPA shows <unknown>/70%.
# DEPENDS ON: nodes (10) because it is a Deployment.   GOES WRONG: HPA stuck on <unknown> = metrics-server not Ready or pods lack resource REQUESTS
# (utilisation % is computed against requests: no requests, no autoscaling).
resource "aws_eks_addon" "metrics_server" {
  cluster_name                = local.eks.cluster_name
  addon_name                  = "metrics-server"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# ----------------------------------------------------------------------------- optional: Cluster Autoscaler
data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# Least privilege: describe is global; modifying capacity is limited to ASGs tagged for THIS cluster.
data "aws_iam_policy_document" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0

  statement {
    sid = "Describe"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ModifyOwnAsgs"
    actions   = ["autoscaling:SetDesiredCapacity", "autoscaling:TerminateInstanceInAutoScalingGroup"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/${local.eks.cluster_name}"
      values   = ["owned"]
    }
  }
}

# WHY:        Cluster Autoscaler is installed only to COMPARE with Karpenter; it needs Auto Scaling group permissions.
# DEPENDS:    Trusted via Pod Identity; used by the cluster-autoscaler ServiceAccount.
# GOES WRONG: Running both CA and Karpenter on the same pods causes double scaling decisions: keep CA scaled to 0 unless experimenting.
resource "aws_iam_role" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0

  name               = "${local.name}-cluster-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

# WHY:        Scoped by ASG tags so it can only scale this cluster's groups.
# DEPENDS:    Depends on the CA role and ASG tags on the node group.
# GOES WRONG: Missing tags = 'no node groups found' and Pending pods are not scaled.
resource "aws_iam_role_policy" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0

  name   = "cluster-autoscaler"
  role   = aws_iam_role.cluster_autoscaler[0].id
  policy = data.aws_iam_policy_document.cluster_autoscaler[0].json
}

# WHY:        Maps the role to the CA ServiceAccount.
# DEPENDS:    Depends on the cluster and Pod Identity agent.
# GOES WRONG: Wrong ServiceAccount name = AccessDenied from the node role.
resource "aws_eks_pod_identity_association" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0

  cluster_name    = local.eks.cluster_name
  namespace       = "kube-system"
  service_account = "cluster-autoscaler"
  role_arn        = aws_iam_role.cluster_autoscaler[0].arn
}

# autoDiscovery: finds ASGs by the tags EKS puts on managed node groups (k8s.io/cluster-autoscaler/enabled and .../<cluster>=owned).
resource "helm_release" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0

  name       = "cluster-autoscaler"
  namespace  = "kube-system"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = var.cluster_autoscaler_chart_version
  timeout    = 300
  wait       = true

  values = [yamlencode({
    cloudProvider = "aws"
    awsRegion     = var.region
    autoDiscovery = { clusterName = local.eks.cluster_name }
    rbac          = { serviceAccount = { create = true, name = "cluster-autoscaler" } }
  })]

  depends_on = [aws_eks_pod_identity_association.cluster_autoscaler, aws_iam_role_policy.cluster_autoscaler]
}
