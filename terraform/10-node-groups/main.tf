# =============================================================================
# 10-node-groups : EC2 worker nodes (managed node group) + CoreDNS
# =============================================================================
#
#   EKS control plane
#        |  kubelet registers using the NODE IAM ROLE (05-iam); EKS creates the access entry (type EC2_LINUX) automatically
#   +----+-----------------------------+
#   | Managed node group "system"      |   ASG across 3 private subnets, nodes carry node-sg (03) + cluster SG (06)
#   +----------------------------------+
#   (Karpenter nodes later, folder 12; Fargate pods, folder 11)
#
# MANAGED NODE GROUP vs KARPENTER: the MNG is a small, fixed, always-on pool that hosts the things that CREATE capacity (Karpenter,
# CoreDNS, LB controller). Karpenter then provisions right-sized, often Spot, nodes for application pods. Karpenter cannot run on
# nodes it creates itself (chicken-and-egg), so the MNG is not optional.
#
# COST: 2 x t3.medium ~ $60/month + EBS. EXPENSIVE-ish: destroy the lab when not in use.

# ---------------------------------------------------------------------------------------------
# LAUNCH TEMPLATE
# ---------------------------------------------------------------------------------------------
# WHY A LAUNCH TEMPLATE (instead of plain MNG settings): it is the only way to (a) attach OUR node security group, (b) force IMDSv2 with
# hop limit 1, (c) encrypt the root volume, (d) tag the instances/volumes for cost allocation.
# SECURITY GROUPS: [node-sg (03), cluster primary SG (06)]. Specifying SGs in a launch template REPLACES the default, so the cluster
# SG must be listed explicitly or nodes cannot reach the control plane. node-sg is the source in the RDS/Redis/EFS rules.
# IMDSv2 + hop limit 1: a pod is one network hop beyond the node, so pods CANNOT query the metadata service and steal the NODE role
# credentials (a real attack path). Consequence: tools that auto-discover region/VPC via IMDS must be given them explicitly
# (the LB controller and the app Helm chart do this).
# GOES WRONG: forgetting the cluster SG => nodes stay NotReady, kubelet cannot reach the API.
resource "aws_launch_template" "system" {
  name_prefix            = "${local.name}-system-"
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
      volume_size           = var.system_disk_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name}-system" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${local.name}-system" })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------------------------
# MANAGED NODE GROUP
# ---------------------------------------------------------------------------------------------
# WHAT:   An Auto Scaling Group that EKS creates and updates for you (AMI selection, drain on update, graceful termination).
#         AL2023 is the supported Linux AMI family for current Kubernetes versions.
# HOW IT JOINS: ASG instance boots -> nodeadm configures kubelet -> kubelet authenticates with the node role -> node appears Ready
#         once the VPC CNI is running on it.
# max_unavailable=1: rolling AMI updates replace one node at a time.
# desired_size is ignored after creation: humans/autoscalers may change it and Terraform must not revert it.
# GOES WRONG: nodes stuck NotReady => CNI add-on unhealthy, wrong SGs, or no route to the API/ECR (check NAT/endpoints, USER_GUIDE 10).
resource "aws_eks_node_group" "system" {
  cluster_name    = local.cluster_name
  node_group_name = "system"
  node_role_arn   = local.node_role_arn
  subnet_ids      = local.private_subnet_ids

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = var.system_capacity_type
  instance_types = var.system_instance_types

  launch_template {
    id      = aws_launch_template.system.id
    version = aws_launch_template.system.latest_version
  }

  scaling_config {
    desired_size = var.system_desired_size
    min_size     = var.system_min_size
    max_size     = var.system_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "cloudcart.io/node-role" = "system"
  }

  dynamic "taint" {
    for_each = var.taint_system_nodes ? [1] : []

    content {
      key    = "CriticalAddonsOnly"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }

  tags = { Name = "${local.name}-system" }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ---------------------------------------------------------------------------------------------
# COREDNS (needs nodes, so it lives here and not in 06-eks)
# ---------------------------------------------------------------------------------------------
# Cluster DNS. Pods resolve names through the cluster DNS Service IP (x.x.x.10), which forwards non-cluster names to the VPC resolver
# (.2). If CoreDNS is down every name lookup in the cluster fails ("Temporary failure in name resolution").
resource "aws_eks_addon" "coredns" {
  cluster_name                = local.cluster_name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.system]
}
