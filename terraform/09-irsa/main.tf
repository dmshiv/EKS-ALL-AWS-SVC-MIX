# =============================================================================
# 09-irsa : IAM Roles for Service Accounts (the original pod-IAM mechanism; required on Fargate)
# =============================================================================
#
# IRSA FLOW
#   1. kubelet projects a signed JWT into the pod (audience sts.amazonaws.com, issuer = the cluster's OIDC URL, subject =
#      system:serviceaccount:<namespace>:<serviceaccount>).
#   2. The EKS pod-identity-webhook sets AWS_ROLE_ARN and AWS_WEB_IDENTITY_TOKEN_FILE from the ServiceAccount ANNOTATION
#      eks.amazonaws.com/role-arn.
#   3. The AWS SDK calls STS AssumeRoleWithWebIdentity with that JWT.
#   4. IAM fetches the OIDC provider (registered in 06-eks), verifies the JWT signature, then evaluates the role TRUST POLICY
#      conditions on aud and sub. If they match, STS returns temporary credentials. 5. SDK calls S3/DynamoDB/... with them.
#
# KEY DIFFERENCE FROM POD IDENTITY (08): the mapping SA -> role lives in TWO places (the SA annotation in Kubernetes AND the role trust
# policy in IAM), and the trust policy hard-codes the cluster's OIDC issuer URL. Forget the `sub` condition and ANY service account
# in the cluster can assume the role: a classic security finding.
#
# WHY KEEP IT: (a) Fargate does not support Pod Identity, (b) many existing clusters/tools still use IRSA, (c) it works outside
# EKS-on-EC2. Interviewers ask for the comparison, so we implement both and test both (USER_GUIDE sections 8 and 9).
# COST: IAM is free.

data "aws_iam_policy_document" "irsa_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    # aud: the token was minted for STS (not for another audience).
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # sub: ONLY these ServiceAccounts. This line IS the security boundary of IRSA.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = [for ns in var.namespaces : "system:serviceaccount:${ns}:${var.service_account_name}"]
    }
  }
}

# WHAT:   A demo role. Its permission (list the product-images bucket) is attached by 15-s3, which owns the bucket.
# WHAT DEPENDS ON IT: 15-s3 (policy), kubernetes/serviceaccounts/irsa-demo.yaml (annotation with this role's ARN), USER_GUIDE test 9.x.
# GOES WRONG: wrong `sub` (typo in namespace/name) => "Not authorized to perform sts:AssumeRoleWithWebIdentity" in the pod logs.
resource "aws_iam_role" "irsa_demo" {
  name               = "${local.name}-irsa-demo"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust.json
}
