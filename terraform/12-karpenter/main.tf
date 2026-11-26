# =============================================================================
# 12-karpenter : just-in-time node provisioning (controller + AWS plumbing)
# =============================================================================
#
#   Pod Pending (Unschedulable)              Karpenter controller (runs on the system node group)
#        |                                        |  1. watches unschedulable pods
#        +--------- scheduler event ------------->|  2. picks the cheapest instance types satisfying requests/affinity/zone
#                                                 |  3. ec2:CreateFleet (Spot or On-Demand) -> instance with NodeClass settings
#                                                 v
#                                       EC2 instance boots -> kubelet joins using the KARPENTER NODE ROLE (access entry EC2_LINUX)
#                                                 |  4. pod scheduled; later: empty/underused nodes are CONSOLIDATED (terminated)
#   Spot interruption notice (EventBridge) -> SQS interruption queue -> Karpenter drains the node BEFORE the 2-minute deadline
#
# KARPENTER vs CLUSTER AUTOSCALER (interview)
#   CA: scales pre-defined Auto Scaling Groups (fixed instance type per group), reacts via ASG, slower (minutes), bin-packing limited
#       to the ASG's shape; you manage many node groups.
#   Karpenter: no ASGs; calls EC2 Fleet directly, chooses from the whole instance catalogue per pending-pod batch, faster, consolidates
#       and replaces nodes proactively, native Spot interruption handling.
#   Karpenter can't run on nodes it manages => the controller lives on the system managed node group (06).
#
# WHO NEEDS WHICH ROLE
#   controller role (Pod Identity)  : calls EC2/IAM/SQS/SSM/Pricing APIs to create instances            (below)
#   node role (instance profile)    : what the NEW nodes' kubelet uses to join/pull images/CNI         (below)
#
# WHAT THIS FOLDER DOES NOT DO: it installs the controller and its AWS plumbing. WHAT Karpenter may build (EC2NodeClass + NodePool,
# Spot vs On-Demand, limits, consolidation) is Kubernetes configuration and lives in kubernetes/karpenter/, applied with
# scripts/deploy-karpenter.sh after this folder (the CRDs must exist first). Terraform = AWS plumbing, kubectl = scheduling policy.

locals {
  cluster_name  = local.eks.cluster_name
  cluster_owned = "kubernetes.io/cluster/${local.cluster_name}"
  region_arn    = "arn:${local.partition}:ec2:${var.region}"
}

# ---------------------------------------------------------------------------------------------
# NODE ROLE for Karpenter-launched nodes (same policies as the managed node group role)
# ---------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# WHY:        Nodes launched by Karpenter need their own role (separate from managed node groups) so the two can be managed independently.
# DEPENDS:    Trusted by ec2.amazonaws.com; referenced by the EC2NodeClass in kubernetes/karpenter.
# GOES WRONG: Role missing from an access entry/aws-auth mapping -> nodes launch but never join the cluster.
resource "aws_iam_role" "node" {
  name               = "${local.name}-karpenter-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

# WHY:        Worker node, CNI, ECR read and SSM core policies for Karpenter nodes.
# DEPENDS:    Depends on the Karpenter node role.
# GOES WRONG: Missing policy -> node joins as NotReady or cannot pull images.
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEC2ContainerRegistryReadOnly",
    "AmazonEKS_CNI_Policy",
    "AmazonSSMManagedInstanceCore",
  ])

  role       = aws_iam_role.node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value}"
}

# WHY:    With authentication_mode=API a node role is NOT automatically trusted. Managed node groups create their own entry;
#         Karpenter nodes need one explicitly. type EC2_LINUX grants exactly the system:nodes permissions kubelets need.
# WITHOUT IT: instances launch (you pay!) but never join: "node not found"/NotReady forever; kubelet logs "Unauthorized".
resource "aws_eks_access_entry" "node" {
  cluster_name  = local.cluster_name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"
}

# ---------------------------------------------------------------------------------------------
# INTERRUPTION HANDLING: EventBridge rules -> SQS queue -> Karpenter
# ---------------------------------------------------------------------------------------------
# The queue name MUST equal what you pass as settings.interruptionQueue (we use the cluster name).
resource "aws_sqs_queue" "interruption" {
  name                      = local.cluster_name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = { Name = "${local.cluster_name}-karpenter-interruption" }
}

data "aws_iam_policy_document" "interruption_queue" {
  statement {
    sid       = "EventBridgeAndSqsMaySend"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.interruption.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.interruption.arn]

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

# WHY:        Only EventBridge may write Spot-interruption and rebalance events into the queue Karpenter reads.
# DEPENDS:    Depends on the interruption queue and the EventBridge rules.
# GOES WRONG: Without it Karpenter never hears about Spot interruptions and nodes disappear without graceful drain.
resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.id
  policy    = data.aws_iam_policy_document.interruption_queue.json
}

# Five signals Karpenter reacts to. Spot interruption = 2 minutes' notice; rebalance = "this Spot capacity is at elevated risk".
locals {
  interruption_events = {
    spot_interruption = {
      source      = "aws.ec2"
      detail_type = "EC2 Spot Instance Interruption Warning"
    }
    rebalance = {
      source      = "aws.ec2"
      detail_type = "EC2 Instance Rebalance Recommendation"
    }
    instance_state_change = {
      source      = "aws.ec2"
      detail_type = "EC2 Instance State-change Notification"
    }
    health = {
      source      = "aws.health"
      detail_type = "AWS Health Event"
    }
    capacity_reservation = {
      source      = "aws.ec2"
      detail_type = "EC2 Capacity Reservation Instance Interruption Warning"
    }
  }
}

# WHY:        Matches EC2 Spot interruption, rebalance, instance state change and scheduled-change events.
# DEPENDS:    Targets the interruption queue; consumed by the Karpenter controller.
# GOES WRONG: Wrong event pattern = silent: no events reach the queue and drain never happens.
resource "aws_cloudwatch_event_rule" "interruption" {
  for_each = local.interruption_events

  name = "${local.cluster_name}-karpenter-${replace(each.key, "_", "-")}"

  event_pattern = jsonencode({
    source        = [each.value.source]
    "detail-type" = [each.value.detail_type]
  })
}

# WHY:        Connects the rule to the SQS queue.
# DEPENDS:    Depends on the rule and queue policy.
# GOES WRONG: Rule without a target drops every event.
resource "aws_cloudwatch_event_target" "interruption" {
  for_each = local.interruption_events

  rule      = aws_cloudwatch_event_rule.interruption[each.key].name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption.arn
}

# ---------------------------------------------------------------------------------------------
# CONTROLLER ROLE (Pod Identity) -- scoped to THIS cluster through resource tags
# ---------------------------------------------------------------------------------------------
# Mirrors the policy in the official Karpenter v1 CloudFormation template. VERIFY against the docs for your chosen version when
# upgrading (permissions are added between releases):
#   https://karpenter.sh/docs/reference/cloudformation/
data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "controller" {
  # Launch capacity: read-only shared resources (AMIs, subnets, SGs) the instance will be attached to.
  statement {
    sid     = "AllowScopedEC2InstanceAccessActions"
    actions = ["ec2:RunInstances", "ec2:CreateFleet"]
    resources = [
      "${local.region_arn}::image/*",
      "${local.region_arn}::snapshot/*",
      "${local.region_arn}:*:security-group/*",
      "${local.region_arn}:*:subnet/*",
      "${local.region_arn}:*:capacity-reservation/*",
      "${local.region_arn}:*:placement-group/*",
    ]
  }

  statement {
    sid       = "AllowScopedEC2LaunchTemplateAccessActions"
    actions   = ["ec2:RunInstances", "ec2:CreateFleet"]
    resources = ["${local.region_arn}:*:launch-template/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.cluster_owned}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  # Creating instances/volumes/etc. is only allowed when the REQUEST tags them as belonging to this cluster.
  statement {
    sid     = "AllowScopedEC2InstanceActionsWithTags"
    actions = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
    resources = [
      "${local.region_arn}:*:fleet/*",
      "${local.region_arn}:*:instance/*",
      "${local.region_arn}:*:volume/*",
      "${local.region_arn}:*:network-interface/*",
      "${local.region_arn}:*:launch-template/*",
      "${local.region_arn}:*:spot-instances-request/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/${local.cluster_owned}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.cluster_name]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid     = "AllowScopedResourceCreationTagging"
    actions = ["ec2:CreateTags"]
    resources = [
      "${local.region_arn}:*:fleet/*",
      "${local.region_arn}:*:instance/*",
      "${local.region_arn}:*:volume/*",
      "${local.region_arn}:*:network-interface/*",
      "${local.region_arn}:*:launch-template/*",
      "${local.region_arn}:*:spot-instances-request/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/${local.cluster_owned}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.cluster_name]
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedResourceTagging"
    actions   = ["ec2:CreateTags"]
    resources = ["${local.region_arn}:*:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.cluster_owned}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }

    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.cluster_name]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["eks:eks-cluster-name", "karpenter.sh/nodeclaim", "Name"]
    }
  }

  # Termination only for instances/templates this cluster's Karpenter created.
  statement {
    sid     = "AllowScopedDeletion"
    actions = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
    resources = [
      "${local.region_arn}:*:instance/*",
      "${local.region_arn}:*:launch-template/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.cluster_owned}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid = "AllowRegionalReadActions"
    actions = [
      "ec2:DescribeCapacityReservations",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribePlacementGroups",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "AllowSSMReadActions"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:${local.partition}:ssm:${var.region}::parameter/aws/service/*"]
  }

  statement {
    sid       = "AllowPricingReadActions"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  statement {
    sid       = "AllowInterruptionQueueActions"
    actions   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
    resources = [aws_sqs_queue.interruption.arn]
  }

  # iam:PassRole is the privilege-escalation-sensitive one: only THIS node role, only to EC2.
  statement {
    sid       = "AllowPassingInstanceRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.node.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  # Karpenter creates/manages instance profiles itself from the EC2NodeClass `role`.
  statement {
    sid       = "AllowScopedInstanceProfileCreationActions"
    actions   = ["iam:CreateInstanceProfile"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:instance-profile/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/${local.cluster_owned}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.cluster_name]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"
      values   = [var.region]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedInstanceProfileTagActions"
    actions   = ["iam:TagInstanceProfile"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:instance-profile/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.cluster_owned}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"
      values   = [var.region]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/${local.cluster_owned}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.cluster_name]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"
      values   = [var.region]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid = "AllowScopedInstanceProfileActions"
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile",
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:instance-profile/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.cluster_owned}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"
      values   = [var.region]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowInstanceProfileReadActions"
    actions   = ["iam:GetInstanceProfile"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:instance-profile/*"]
  }

  statement {
    sid       = "AllowUnscopedInstanceProfileListAction"
    actions   = ["iam:ListInstanceProfiles"]
    resources = ["*"]
  }

  # Lets Karpenter drain a zone when ARC Zonal Shift moves traffic away from it.
  statement {
    sid       = "AllowZonalShiftStatusReadOnly"
    actions   = ["arc-zonal-shift:GetManagedResource"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "arc-zonal-shift:ResourceIdentifier"
      values   = [local.eks.cluster_arn]
    }
  }

  statement {
    sid       = "AllowAPIServerEndpointDiscovery"
    actions   = ["eks:DescribeCluster"]
    resources = [local.eks.cluster_arn]
  }
}

# WHY:        The Karpenter controller needs EC2 Fleet, pricing, SSM and IAM PassRole permissions to provision nodes.
# DEPENDS:    Trusted by pods.eks.amazonaws.com (Pod Identity); used by the karpenter ServiceAccount.
# GOES WRONG: AccessDenied in the controller log (UnauthorizedOperation / iam:PassRole) = this role or its policy.
resource "aws_iam_role" "controller" {
  name               = "${local.name}-karpenter-controller"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

# WHY:        Least-privilege inline policy scoped by cluster tag so Karpenter can only touch its own nodes.
# DEPENDS:    Depends on the controller role; requires the discovery tags set in 01-vpc/03-security-groups.
# GOES WRONG: Missing tag conditions or tags = 'no subnets/security groups found' and Pods stay Pending.
resource "aws_iam_role_policy" "controller" {
  name   = "karpenter-controller"
  role   = aws_iam_role.controller.id
  policy = data.aws_iam_policy_document.controller.json
}

# WHY:        Binds the controller role to the karpenter ServiceAccount: credentials come from the Pod Identity agent, no annotations or OIDC needed.
# DEPENDS:    Depends on the cluster, role and the Pod Identity agent add-on (08-pod-identity).
# GOES WRONG: Wrong namespace/ServiceAccount name = controller falls back to the node role and gets AccessDenied.
resource "aws_eks_pod_identity_association" "controller" {
  cluster_name    = local.cluster_name
  namespace       = "kube-system"
  service_account = "karpenter"
  role_arn        = aws_iam_role.controller.arn
}

# ---------------------------------------------------------------------------------------------
# CONTROLLER (Helm, OCI chart from public ECR)
# ---------------------------------------------------------------------------------------------
# Pinned to the system nodes (nodeSelector) so it never lands on a node it manages.
# GOES WRONG:
#   - helm pull 403 from public.ecr.aws  -> stale ECR credentials in ~/.docker/config.json; run `docker logout public.ecr.aws`.
#   - controller CrashLoop "no credentials" -> Pod Identity association missing/typo (namespace kube-system, SA karpenter).
resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version
  timeout    = 600
  wait       = true

  values = [yamlencode({
    replicas = var.controller_replicas

    serviceAccount = {
      name = "karpenter"
    }

    settings = {
      clusterName       = local.cluster_name
      interruptionQueue = aws_sqs_queue.interruption.name
    }

    nodeSelector = {
      "cloudcart.io/node-role" = "system"
    }

    tolerations = [{
      key      = "CriticalAddonsOnly"
      operator = "Exists"
    }]

    controller = {
      # Region is passed explicitly: nodes enforce IMDSv2 hop limit 1, so pods cannot discover it from the metadata service.
      env = [{ name = "AWS_REGION", value = var.region }]
      resources = {
        requests = { cpu = "250m", memory = "512Mi" }
        limits   = { memory = "1Gi" }
      }
    }
  })]

  depends_on = [
    aws_eks_pod_identity_association.controller,
    aws_iam_role_policy.controller,
    aws_eks_access_entry.node,
    aws_cloudwatch_event_target.interruption,
  ]
}
