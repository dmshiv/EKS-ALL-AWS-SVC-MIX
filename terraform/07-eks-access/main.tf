# =============================================================================
# 07-eks-access : who may use the Kubernetes API (humans and CI)
# =============================================================================
#
#   human/CI  --aws sts / eks get-token-->  EKS authenticator
#                 (1) AUTHENTICATION: IAM proves WHO you are (SigV4-presigned STS call)
#                 (2) ACCESS ENTRY maps the IAM principal -> a Kubernetes identity
#                 (3) AUTHORIZATION: EKS access policy (managed ClusterRole-like) and/or Kubernetes RBAC
#                                    bindings decide WHAT you can do
#
# WHERE EACH LAYER OPERATES (the interview cheat-sheet)
#   AWS IAM            : may you call AWS APIs (eks:DescribeCluster, s3:GetObject...)?  Evaluated by AWS.
#   EKS Access Entry   : maps an IAM principal to Kubernetes user/groups + access policy. Replaces aws-auth.
#   Kubernetes RBAC    : may that user/group do verb X on resource Y in namespace Z?    Evaluated by the API server.
#   NetworkPolicy      : may pod A talk to pod B?                                        Enforced on the node (CNI).
#   Security Group     : may this ENI accept this packet?                                Enforced by the VPC.
#
# Access entries are an AWS API (auditable in CloudTrail, manageable in Terraform, no lock-out through a bad
# ConfigMap edit), which is why the cluster runs with authentication_mode = "API".

locals {
  roles = {
    # May view everything (cluster scope), change nothing. Good for on-call/auditors.
    readonly = {
      policy_arn = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
      scope_type = "cluster"
      namespaces = []
    }
    # May edit workloads ONLY in the developer namespace. Cannot touch other namespaces or cluster resources.
    developer = {
      policy_arn = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
      scope_type = "namespace"
      namespaces = [var.developer_namespace]
    }
  }
}

# WHY:    Real people/CI should assume a role (temporary credentials) instead of using IAM users with keys.
# TRUST:  any principal in this account that ALSO has sts:AssumeRole permission on the role. PRODUCTION: trust your
#         IdP/SSO permission-set roles explicitly and require MFA (aws:MultiFactorAuthPresent).
data "aws_iam_policy_document" "assume_account" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }
}

# WHY:        A human/CI admin role mapped to the cluster through an Access Entry, replacing the old aws-auth ConfigMap.
# DEPENDS:    Depends on the account principal that may assume it; mapped by the access entry below.
# GOES WRONG: Assuming a role that is not mapped gives 'You must be logged in to the server (Unauthorized)'.
resource "aws_iam_role" "access" {
  for_each = local.roles

  name               = "${local.name}-eks-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.assume_account.json
}

# The role needs eks:DescribeCluster so `aws eks update-kubeconfig` can read the endpoint/CA. It grants NO Kubernetes rights.
data "aws_iam_policy_document" "describe_cluster" {
  statement {
    actions   = ["eks:DescribeCluster"]
    resources = [data.terraform_remote_state.eks.outputs.cluster_arn]
  }
}

# WHY:        kubeconfig generation calls eks:DescribeCluster; the role needs only that to bootstrap.
# DEPENDS:    Depends on the access role.
# GOES WRONG: Missing -> aws eks update-kubeconfig fails with AccessDenied before kubectl is even tried.
resource "aws_iam_role_policy" "describe_cluster" {
  for_each = local.roles

  name   = "eks-describe-cluster"
  role   = aws_iam_role.access[each.key].id
  policy = data.aws_iam_policy_document.describe_cluster.json
}

# WHAT:   The access entry says "this IAM role is a Kubernetes principal of this cluster".
# WITHOUT IT: the role authenticates but is rejected: "You must be logged in to the server (Unauthorized)".
resource "aws_eks_access_entry" "access" {
  for_each = local.roles

  cluster_name  = local.cluster_name
  principal_arn = aws_iam_role.access[each.key].arn
  type          = "STANDARD"
}

# WHAT:   Attaches an AWS-managed access policy (a curated set of Kubernetes permissions) with a scope.
#         namespace-scoped => the developer cannot see/modify anything outside the listed namespaces.
resource "aws_eks_access_policy_association" "access" {
  for_each = local.roles

  cluster_name  = local.cluster_name
  principal_arn = aws_iam_role.access[each.key].arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.scope_type
    namespaces = each.value.scope_type == "namespace" ? each.value.namespaces : null
  }

  depends_on = [aws_eks_access_entry.access]
}

# Extra human admins (e.g. your SSO role) so you are not locked out if the original creator identity changes.
resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.extra_admin_principal_arns)

  cluster_name  = local.cluster_name
  principal_arn = each.value
  type          = "STANDARD"
}

# WHY:        IAM permission to call EKS is not Kubernetes permission: this grants the mapped role cluster-admin through an AWS managed access policy.
# DEPENDS:    Depends on the access entry; the scope can be cluster-wide or namespace-limited.
# GOES WRONG: Entry without a policy association authenticates but is authorized to do nothing (Forbidden on every command).
resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.extra_admin_principal_arns)

  cluster_name  = local.cluster_name
  principal_arn = each.value
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}
