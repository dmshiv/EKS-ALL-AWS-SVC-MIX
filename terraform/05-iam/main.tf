# =============================================================================
# 05-iam : service roles that AWS itself assumes (cluster, nodes, Fargate)
# =============================================================================
#
# THREE KINDS OF IAM IDENTITY IN THIS PROJECT (do not mix them up)
#   1. SERVICE ROLES (this folder): assumed by an AWS SERVICE (eks, ec2, eks-fargate-pods). Trust principal = service.
#   2. WORKLOAD ROLES (08-pod-identity, 09-irsa): assumed by PODS through the ServiceAccount. Trust principal = pods.eks.amazonaws.com
#      or the cluster's OIDC provider.
#   3. HUMAN/CI ROLES (07-eks-access, 46-cicd): assumed by people or pipelines; mapped into Kubernetes by access entries.
#
#   IAM role = identity with permissions and NO long-lived credentials.   STS = the service that hands out the temporary
#   credentials when a role is assumed (AssumeRole / AssumeRoleWithWebIdentity). IAM user = long-lived keys: never used here.
#
# WHY A SEPARATE FOLDER: roles change rarely and are reviewed by security; keeping them out of 06-eks / 10-node-groups lets you
# review "who can do what" in one place and keep cluster rebuilds from recreating identities.
# COST: IAM is free.

# ---------------------------------------------------------------------------------------------
# CLUSTER ROLE
# ---------------------------------------------------------------------------------------------
# WHY:    The EKS control plane acts in YOUR account: it creates/attaches the cross-account ENIs, describes subnets/SGs,
#         manages SG-for-Pods trunk ENIs (VPCResourceController).
# HOW:    Trust policy lets eks.amazonaws.com call sts:AssumeRole. The managed policy supplies the EC2/ELB calls.
# DEPENDS ON: nothing.  USED BY: 06-eks (aws_eks_cluster.role_arn). 06-eks adds an inline KMS policy for Secrets encryption.
# GOES WRONG: delete the role/policy => cluster degrades (cannot manage ENIs); a typo in the trust policy => cluster creation fails.
data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

# WHY:        The EKS control plane assumes this role to manage ENIs, load balancers and security groups in your account.
# DEPENDS:    Trusted by eks.amazonaws.com; used by 06-eks.
# GOES WRONG: A wrong trust policy makes cluster creation fail immediately; deleting the role while the cluster exists breaks the control plane.
resource "aws_iam_role" "cluster" {
  name               = "${local.name}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
}

# WHY:        Attaches the AWS managed cluster policy so the control plane can operate.
# DEPENDS:    Depends on the cluster role; must exist before 06-eks creates the cluster.
# GOES WRONG: Applied after the cluster -> cluster creation hits AccessDenied.
resource "aws_iam_role_policy_attachment" "cluster" {
  for_each = toset([
    "AmazonEKSClusterPolicy",
    "AmazonEKSVPCResourceController", # needed for Security Groups for Pods (folder 43)
  ])

  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value}"
}

# ---------------------------------------------------------------------------------------------
# NODE ROLE (managed node group, folder 10)
# ---------------------------------------------------------------------------------------------
# WHY:    The kubelet and VPC CNI on each node call AWS APIs: join the cluster, pull images from ECR, attach ENIs.
# WHO USES IT: the EC2 instance profile of managed-node-group nodes. NOT application pods: giving the node role S3/DynamoDB
#         access would hand those rights to EVERY pod on the node, which is exactly why Pod Identity/IRSA exist.
# POLICIES
#   AmazonEKSWorkerNodePolicy           : describe cluster/EC2 for kubelet bootstrap
#   AmazonEC2ContainerRegistryReadOnly  : kubelet pulls images from ECR (this is how EKS "pulls from ECR")
#   AmazonEKS_CNI_Policy                : VPC CNI manages ENIs and secondary IPs/prefixes
#   AmazonSSMManagedInstanceCore        : shell into nodes with SSM Session Manager (no SSH keys, no bastion)
# GOES WRONG: missing ECR policy => ImagePullBackOff "no basic auth credentials"; missing CNI policy => pods stuck ContainerCreating.
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# WHY:        EC2 worker nodes use this role for kubelet registration and ECR image pulls; it is NOT the application identity (Pod Identity/IRSA roles are).
# DEPENDS:    Trusted by ec2.amazonaws.com; used by 10-node-groups and 45-prefix-delegation.
# GOES WRONG: Giving app permissions to this role means EVERY pod on the node inherits them: a classic least-privilege violation.
resource "aws_iam_role" "node" {
  name               = "${local.name}-eks-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

# WHY:        Worker node, CNI and ECR read-only managed policies are the minimum for nodes to join and pull images.
# DEPENDS:    Depends on the node role.
# GOES WRONG: Missing ECR read policy -> ImagePullBackOff with 'no basic auth credentials'; missing worker policy -> nodes never become Ready.
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

# ---------------------------------------------------------------------------------------------
# FARGATE POD EXECUTION ROLE (folder 11)
# ---------------------------------------------------------------------------------------------
# WHY:    On Fargate there is no node role. This role lets the Fargate infrastructure (not your code) pull the image from ECR and
#         write logs. Application AWS access on Fargate must use IRSA (Pod Identity is not supported on Fargate).
# SECURITY: the aws:SourceArn condition limits it to Fargate profiles of THIS cluster (confused-deputy protection).
data "aws_iam_policy_document" "fargate_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks-fargate-pods.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:eks:${var.region}:${local.account_id}:fargateprofile/${local.name}/*"]
    }
  }
}

# WHY:        Fargate's pod execution role pulls images and ships logs on behalf of Fargate pods.
# DEPENDS:    Trusted by eks-fargate-pods.amazonaws.com; used by 11-fargate.
# GOES WRONG: A trust policy without the source-ARN condition is too broad; a missing role leaves pods Pending.
resource "aws_iam_role" "fargate" {
  name               = "${local.name}-eks-fargate"
  assume_role_policy = data.aws_iam_policy_document.fargate_assume.json
}

# WHY:        AWS managed execution policy lets Fargate pull from ECR and write logs.
# DEPENDS:    Depends on the fargate role.
# GOES WRONG: Without it Fargate pods fail to pull images.
resource "aws_iam_role_policy_attachment" "fargate" {
  role       = aws_iam_role.fargate.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}
