# =============================================================================
# 08-pod-identity : IAM for Pods with EKS Pod Identity (roles + associations)
# =============================================================================
#
# THE PROBLEM: the product-service pod must call DynamoDB/S3. Options, worst to best:
#   X  AWS access keys in a Secret/env/image  -> long-lived, leakable, rotated by hand, readable by anyone with kubectl access
#   X  Node IAM role                          -> every pod on the node (including a compromised one) gets the same rights
#   OK IRSA (09-irsa)                         -> per-ServiceAccount role via the cluster OIDC provider
#   OK EKS Pod Identity (this folder)         -> per-ServiceAccount role via an EKS-managed association (preferred)
#
# EKS POD IDENTITY FLOW
#   Pod (ServiceAccount cloudcart/product-service)
#     |  AWS SDK default credential chain finds AWS_CONTAINER_CREDENTIALS_FULL_URI (injected by the EKS Pod Identity webhook)
#     v
#   Pod Identity Agent (DaemonSet on the node, 169.254.170.23)   [06-eks add-on]
#     |  calls eks-auth:AssumeRoleForPodIdentity with the pod's projected ServiceAccount token
#     v
#   EKS Auth service: looks up the ASSOCIATION (cluster, namespace, serviceaccount) -> role ARN
#     |  the role trust policy must allow principal pods.eks.amazonaws.com (sts:AssumeRole + sts:TagSession)
#     v
#   Temporary credentials (STS, auto-refreshed) -> SDK -> DynamoDB / S3 / SQS ...
#   CloudTrail shows the role session tagged with the cluster, namespace and service account.
#
# WHO OWNS THE PERMISSIONS? This folder creates the ROLES (identity + trust) and the ASSOCIATIONS only. The permissions are attached
# by the folder that OWNS each resource: 15-s3 attaches "read/write images" to product-service, 19-rds attaches "read DB secret" to
# order-service, 22-sqs attaches send/receive, and so on. Benefits: a data-tier folder can be reviewed on its own ("who may touch my
# bucket?"), and a role never references an ARN that does not exist yet. Each folder reads role_names from this folder's state.
#
# POD IDENTITY vs IRSA (interview)
#   + Pod Identity: no OIDC provider, the trust policy is identical for every cluster/role, a role is reusable across clusters,
#     associations are an AWS API (Terraform/CloudTrail friendly), session tags enable ABAC, no annotation on the ServiceAccount.
#   + IRSA: works on FARGATE and outside EKS-on-EC2 (EKS Anywhere, self-managed), works with older SDKs.
#   - Pod Identity: needs the agent add-on, NOT supported on Fargate or Windows nodes, needs a recent SDK.
#   - IRSA: the trust policy contains the cluster-specific OIDC URL; reusing a role in another cluster means editing trust.
#   Rule of thumb: Pod Identity by default; IRSA for Fargate or anything outside plain EKS-on-EC2.

locals {
  # The frontend is intentionally ABSENT: it serves static files and calls only in-cluster Services, so it gets no AWS identity.
  # "No role at all" is the strongest least-privilege posture.
  workloads = toset(["product-service", "order-service", "worker"])
}

# TRUST POLICY (same for every workload role)
# WHY these two actions: AssumeRole obtains the credentials; TagSession lets EKS stamp session tags (eks-cluster-name,
# kubernetes-namespace, kubernetes-service-account) used for ABAC and audit.
data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# WHAT:   One IAM role per workload (blast radius = one service).
# DEPENDS ON: nothing but the trust document. USED BY: the associations below and every data folder that attaches a policy.
resource "aws_iam_role" "workload" {
  for_each = local.workloads

  name               = "${local.name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

# THE LINK between Kubernetes and IAM: "any pod using ServiceAccount <ns>/<name> in <cluster> may assume <role>".
# No annotation on the ServiceAccount is needed. The ServiceAccount does not even have to exist yet.
# WITHOUT IT: the pod gets NoCredentialsError (or falls back to the NODE role and gets AccessDenied) -> see USER_GUIDE failure tests.
# GOES WRONG: a typo in namespace/service-account silently yields no credentials; pods started BEFORE the association must restart.
resource "aws_eks_pod_identity_association" "workload" {
  for_each = local.workloads

  cluster_name    = local.cluster_name
  namespace       = var.namespace
  service_account = each.key
  role_arn        = aws_iam_role.workload[each.key].arn
}
