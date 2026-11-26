# =============================================================================
# 45-prefix-delegation : many more pods per node (VPC CNI prefix delegation)
# =============================================================================
#
# DEFAULT MODE (secondary IPs): each node ENI holds a limited number of secondary IPs; every pod consumes one. Max pods =
#   ENIs x (IPs per ENI - 1) + 2. A t3.medium: 3 ENIs x 5 IPs => 17 pods; m5.large: 3 x 9 => 29 pods. Subnets also drain fast: every
#   pod is one VPC IP.
# PREFIX DELEGATION: instead of single IPs the CNI asks EC2 to assign /28 PREFIXES (16 IPs) to each ENI slot. Same ENIs, ~16x the addresses:
#   m5.large can run 110 pods. The IPAM daemon (ipamd) carves pod IPs out of the prefixes; WARM_PREFIX_TARGET=1 keeps a spare /28 ready.
#
#   VPC subnet (/20) --EC2 AssignPrivateIpAddresses(Ipv4PrefixCount)--> node ENI slot gets a /28 --> ipamd hands pod IPs from it
#
# TWO SWITCHES ARE NEEDED (the classic mistake is flipping only one):
#   1. CNI:     ENABLE_PREFIX_DELEGATION=true on the vpc-cni add-on     (06-eks variable vpc_cni_prefix_delegation = true)
#   2. kubelet: maxPods must be raised, otherwise the kubelet still caps pods at the old ENI-based number. This folder's node group sets
#               maxPods via the AL2023 nodeadm NodeConfig in the launch template user data. (Karpenter computes it from the EC2NodeClass.)
# CAVEATS: needs Nitro instances; every /28 must be a CONTIGUOUS free block in the subnet, so a fragmented subnet can fail to assign
#   prefixes ("InsufficientCidrBlocks") even with free IPs: use big subnets or subnet CIDR reservations; existing nodes must be replaced to
#   pick up the new maxPods; the cost is less IP waste but coarser allocation.
# EXPERIMENT (USER_GUIDE section 32): deploy kubernetes/prefix-delegation/pods-scale.yaml with 60 replicas pinned to this node group and
# watch them all schedule on ONE node, then compare with the system node group where they stay Pending.
# COST: one m5.large (~$70/month, destroy after the lab) when enabled. Disabled by default.
# DEPENDS ON: 01-vpc, 03-security-groups, 05-iam, 06-eks (with prefix delegation enabled).

# WHY:        Prefix delegation is a CNI and node-level setting (max-pods raised): this template carries the user-data/limits.
# DEPENDS:    Depends on the node group's AMI settings; used by the pd node group.
# GOES WRONG: Existing nodes keep the old max-pods: only NEW nodes from this template benefit.
resource "aws_launch_template" "pd" {
  count = var.enable_prefix_delegation_nodegroup ? 1 : 0

  name_prefix            = "${local.name}-pd-"
  update_default_version = true

  vpc_security_group_ids = [local.node_sg_id, local.cluster_sg_id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # AL2023 nodes are configured by nodeadm. Managed node groups MERGE this part with their own bootstrap configuration.
  user_data = base64encode(<<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="CLOUDCART"

    --CLOUDCART
    Content-Type: application/node.eks.aws

    ---
    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      kubelet:
        config:
          maxPods: ${var.max_pods}
    --CLOUDCART--
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name}-pd" })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# WHY:        A dedicated node group to demonstrate higher pod density without touching the main node group.
# DEPENDS:    Depends on the launch template, node role and private subnets.
# GOES WRONG: Subnet fragmentation can prevent /28 prefix allocation even with free IPs (InsufficientCidrBlocks).
resource "aws_eks_node_group" "pd" {
  count = var.enable_prefix_delegation_nodegroup ? 1 : 0

  cluster_name    = local.cluster_name
  node_group_name = "prefix-delegation"
  node_role_arn   = local.node_role_arn
  subnet_ids      = local.private_subnet_ids

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = var.instance_types

  launch_template {
    id      = aws_launch_template.pd[0].id
    version = aws_launch_template.pd[0].latest_version
  }

  scaling_config {
    desired_size = 1
    min_size     = 0
    max_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  # Pods in the lab opt in through nodeSelector; nothing else lands here.
  labels = {
    "cloudcart.io/node-role" = "prefix-delegation"
  }

  taint {
    key    = "cloudcart.io/lab"
    value  = "prefix-delegation"
    effect = "NO_SCHEDULE"
  }

  tags = { Name = "${local.name}-pd" }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
