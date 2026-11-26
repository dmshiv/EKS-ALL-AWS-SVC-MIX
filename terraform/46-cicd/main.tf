# =============================================================================
# 46-cicd : keyless CI/CD from GitHub Actions (OIDC federation)
# =============================================================================
#
#   git push main
#     -> GitHub Actions job (gets a short-lived OIDC JWT: iss=token.actions.githubusercontent.com, sub=repo:OWNER/REPO:ref:refs/heads/main)
#     -> aws-actions/configure-aws-credentials -> STS AssumeRoleWithWebIdentity (trust below)  => 1h temporary credentials
#     -> docker build + Trivy scan -> docker push to ECR (immutable git-sha tag)
#     -> helm upgrade --install ... --set image.tag=<sha>  (authenticates to EKS through an ACCESS ENTRY for this same role)
#
# NO STORED SECRETS: there is no AWS_ACCESS_KEY_ID in GitHub. A leaked workflow log or fork cannot reuse anything: credentials expire in
# an hour and the trust policy only accepts tokens from THIS repo and branch. This is the same identity idea as IRSA, applied to CI.
#
# CI/CD vs GITOPS (47-gitops): here the pipeline PUSHES to the cluster (needs cluster credentials). With GitOps (Argo CD) the pipeline only commits
# a new image tag to Git and an agent INSIDE the cluster PULLS the change: no cluster credentials in CI, drift is auto-corrected, rollback = git revert.
# COST: none (GitHub-hosted runners are billed by GitHub, not AWS).

# WHY:        Lets GitHub Actions authenticate to AWS with short-lived OIDC tokens: no stored access keys anywhere.
# DEPENDS:    Used by the deploy role trust policy.
# GOES WRONG: Only one provider per URL per account: apply fails if it already exists.
resource "aws_iam_openid_connect_provider" "github" {
  count = local.enabled && var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = local.enabled && !var.create_github_oidc_provider ? 1 : 0

  url = "https://token.actions.githubusercontent.com"
}

locals {
  github_provider_arn = !local.enabled ? "" : (var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn)
}

# TRUST: the `sub` condition is the security boundary. Without it ANY GitHub repository could assume this role.
data "aws_iam_policy_document" "trust" {
  count = local.enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

# WHY:        The role the pipeline assumes; the trust policy restricts it to one repository and branch.
# DEPENDS:    Depends on the OIDC provider.
# GOES WRONG: A trust 'sub' that is too broad lets any repo in your org assume it.
resource "aws_iam_role" "deploy" {
  count = local.enabled ? 1 : 0

  name               = "${local.name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.trust[0].json
}

# Least privilege: push to the four CloudCart repositories only; GetAuthorizationToken cannot be resource-scoped (AWS limitation).
data "aws_iam_policy_document" "deploy" {
  count = local.enabled ? 1 : 0

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:DescribeImageScanFindings",
    ]
    resources = values(local.out.ecr.repository_arns)
  }

  statement {
    sid       = "KubeconfigLookup"
    actions   = ["eks:DescribeCluster"]
    resources = [local.out.eks.cluster_arn]
  }
}

# WHY:        Least privilege for the pipeline: push to ECR and describe the cluster, nothing else.
# DEPENDS:    Depends on 04-ecr repository ARNs.
# GOES WRONG: Missing ecr:GetAuthorizationToken fails the docker login step.
resource "aws_iam_role_policy" "deploy" {
  count = local.enabled ? 1 : 0

  name   = "ecr-push-and-describe-cluster"
  role   = aws_iam_role.deploy[0].id
  policy = data.aws_iam_policy_document.deploy[0].json
}

# KUBERNETES SIDE: IAM only gets the pipeline TO the API. The access entry + namespace-scoped edit policy decides what it may DO there
# (deploy in `cloudcart`, nothing else; no cluster-admin, cannot read other namespaces' secrets).
resource "aws_eks_access_entry" "deploy" {
  count = local.enabled ? 1 : 0

  cluster_name  = local.out.eks.cluster_name
  principal_arn = aws_iam_role.deploy[0].arn
  type          = "STANDARD"
}

# WHY:        Kubernetes-side authorization for the pipeline role (IAM allows calling EKS; this allows changing objects).
# DEPENDS:    Depends on an access entry for the deploy role and the namespace scope.
# GOES WRONG: Authenticated but Forbidden on helm upgrade = this association missing.
resource "aws_eks_access_policy_association" "deploy" {
  count = local.enabled ? 1 : 0

  cluster_name  = local.out.eks.cluster_name
  principal_arn = aws_iam_role.deploy[0].arn
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [var.deploy_namespace]
  }

  depends_on = [aws_eks_access_entry.deploy]
}
