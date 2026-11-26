# =============================================================================
# 06-eks : the managed Kubernetes control plane
# =============================================================================
#
#   AWS-managed account (you never see it)            YOUR account / VPC
#   +-----------------------------------+             +--------------------------------------+
#   | API server x2+, etcd x3 (multi-AZ)|<--X-ENIs--->| "EKS-managed ENIs" in private subnets|
#   +-----------------------------------+             |  (kubelets talk to the API through   |
#            ^ public endpoint (optional)             |   these; API talks to kubelets back) |
#            |                                        +--------------------------------------+
#         kubectl / helm / CI
#
# WHAT YOU PAY FOR: $0.10/h (~$73/month) per cluster in STANDARD support, whether or not it has nodes.
# AUTHENTICATION: IAM (aws eks get-token -> STS presigned URL) proves WHO you are;
#                 EKS Access Entries / Kubernetes RBAC decide WHAT you may do (see 07-eks-access).
# LAB vs PRODUCTION: public+private endpoint (lab) vs private-only + VPN/CI inside the VPC (production), restricted CIDRs.

# ---------------------------------------------------------------------------------------------
# KMS permission on the cluster role (the role itself lives in 05-iam)
# ---------------------------------------------------------------------------------------------
# WHY:    Envelope encryption: the API server calls KMS with the CLUSTER ROLE to wrap/unwrap the data keys that encrypt
#         Kubernetes Secrets in etcd. Scoped to the one key (least privilege).
# GOES WRONG: without it cluster creation fails ("KMS key ... is not authorized") or Secrets cannot be decrypted later.
data "aws_iam_policy_document" "cluster_kms" {
  statement {
    sid = "UseSecretsKey"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ListGrants",
      "kms:DescribeKey",
    ]
    resources = [local.eks_key_arn]
  }
}

# WHY:        Envelope-encrypting Kubernetes Secrets needs the control-plane role to use the KMS key.
# DEPENDS:    Depends on the cluster role and the key from 16-kms.
# GOES WRONG: Missing -> cluster creation/update fails with a KMS access error.
resource "aws_iam_role_policy" "cluster_kms" {
  name   = "eks-secrets-kms"
  role   = local.cluster_role_name
  policy = data.aws_iam_policy_document.cluster_kms.json
}

# ---------------------------------------------------------------------------------------------
# CONTROL-PLANE LOGS
# ---------------------------------------------------------------------------------------------
# WHY:    Pre-creating the log group lets us set retention; otherwise EKS creates it with infinite retention (a silent cost).
#         The audit log answers "who deleted that Deployment?".
# COST:   CloudWatch ingestion ~$0.50/GB; audit logs are chatty. Keep types minimal in a lab.
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.name}/cluster"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------------------------------------
# THE CLUSTER
# ---------------------------------------------------------------------------------------------
# WHY / WHAT: the Kubernetes API + etcd + scheduler + controllers.
# KEY CHOICES
#  - authentication_mode = "API": ONLY EKS Access Entries decide who can log in (no aws-auth ConfigMap).
#  - bootstrap_cluster_creator_admin_permissions: whoever runs terraform gets admin once; real people/roles are then managed
#    declaratively in 07-eks-access.
#  - bootstrap_self_managed_addons = false: EKS will NOT silently install vpc-cni/kube-proxy/coredns as unmanaged objects; we install
#    them as EKS add-ons so Terraform owns versions/config. (Cannot be changed later without recreating the cluster.)
#  - subnet_ids = private only: the cross-account ENIs live in private subnets. Load balancers still land in public subnets
#    because of the subnet tags set in 01-vpc.
#  - encryption_config: Secrets in etcd encrypted with our CMK (16-kms).
#  - upgrade_policy STANDARD: auto-upgrade when a version leaves standard support instead of moving to (expensive) extended support.
#  - ip_family: ipv4 here; IPv6 is a creation-time choice (see 44-ipv6).
# DEPENDS ON: 05-iam (role), 01-vpc (subnets), 16-kms (key).  DEPENDED ON BY: everything that talks to the cluster.
# GOES WRONG: creation takes ~10-15 minutes, do not interrupt. Public endpoint + 0.0.0.0/0 is fine for a lab, never for production.
resource "aws_eks_cluster" "this" {
  name     = local.name
  version  = var.kubernetes_version
  role_arn = local.cluster_role_arn

  bootstrap_self_managed_addons = false

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = local.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : null
  }

  kubernetes_network_config {
    ip_family = var.ip_family
  }

  encryption_config {
    provider {
      key_arn = local.eks_key_arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = var.cluster_log_types

  upgrade_policy {
    support_type = "STANDARD"
  }

  depends_on = [
    aws_iam_role_policy.cluster_kms,
    aws_cloudwatch_log_group.cluster,
  ]
}

# WHY:    Karpenter (12) finds the SGs for the nodes it launches through this tag. EKS creates the "cluster primary security group"
#         itself, so we can only tag it afterwards. Nodes carry BOTH this SG and our node SG (03).
resource "aws_ec2_tag" "cluster_sg_discovery" {
  resource_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = local.name
}

# ---------------------------------------------------------------------------------------------
# OIDC PROVIDER (for IRSA, folder 09)
# ---------------------------------------------------------------------------------------------
# WHY:    Each cluster is an OIDC identity issuer that signs ServiceAccount JWTs. Registering that issuer in IAM lets
#         sts:AssumeRoleWithWebIdentity trust those tokens => IRSA.
# FLOW:   Pod projected token (JWT, aud=sts.amazonaws.com) -> AWS SDK -> STS AssumeRoleWithWebIdentity -> IAM validates the signature
#         against this provider -> temporary credentials.
# NOTE:   EKS Pod Identity does NOT need this. We create it for the IRSA lab (09-irsa) and Fargate.
resource "aws_iam_openid_connect_provider" "this" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}

# ---------------------------------------------------------------------------------------------
# ADD-ONS THAT MUST EXIST BEFORE NODES (they are DaemonSets, valid with zero nodes)
# CoreDNS (a Deployment needing nodes) is installed in 10-node-groups.
# ---------------------------------------------------------------------------------------------
# VPC CNI: gives every Pod a real VPC IP from the node's ENIs. Credentials come from the NODE role (AmazonEKS_CNI_Policy in 05-iam).
#   ENABLE_PREFIX_DELEGATION : hand out /28 prefixes -> many more pods per node (lab in 45-prefix-delegation).
#   ENABLE_POD_ENI           : Security Groups for Pods via trunk/branch ENIs (lab in 43-security-groups-for-pods).
#   enableNetworkPolicy      : the CNI's eBPF NetworkPolicy enforcement (lab in 42-network-policies).
# GOES WRONG: toggling these changes IP allocation; existing nodes need replacing to get a new max-pods value.
locals {
  vpc_cni_config = {
    enableNetworkPolicy = tostring(var.vpc_cni_network_policy)
    env = {
      ENABLE_PREFIX_DELEGATION = tostring(var.vpc_cni_prefix_delegation)
      WARM_PREFIX_TARGET       = "1"
      ENABLE_POD_ENI           = tostring(var.vpc_cni_pod_eni)
    }
  }
}

# WHY:        Configures the VPC CNI: network policy enforcement and (optionally) prefix delegation are add-on settings, not Kubernetes manifests.
# DEPENDS:    Depends on the cluster; affects pod IP allocation and NetworkPolicy behaviour for all nodes.
# GOES WRONG: enableNetworkPolicy=false silently ignores NetworkPolicy objects; changing prefix delegation only affects NEW nodes.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  configuration_values        = jsonencode(local.vpc_cni_config)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# kube-proxy: programs iptables rules so Service ClusterIPs reach Pods.
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# EKS Pod Identity Agent: DaemonSet (hostNetwork) that answers credential requests from Pods at 169.254.170.23. It exchanges the Pod's
# identity for temporary IAM credentials via the EKS Auth API. Every workload role in 08-pod-identity depends on it.
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}
