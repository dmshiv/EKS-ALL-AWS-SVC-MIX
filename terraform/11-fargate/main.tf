# =============================================================================
# 11-fargate : serverless pods for ONE demo namespace
# =============================================================================
#
#   Pod in namespace fargate-demo --> matches the profile selector --> scheduler places it on a Fargate "node" (one micro-VM per pod)
#   The pod execution role (05-iam) pulls the image from ECR and ships logs; it is NOT the application's identity.
#
# WHEN FARGATE MAKES SENSE: bursty or isolated workloads where you do not want to manage nodes; each pod gets its own kernel.
# WHEN NOT: DaemonSets (unsupported), GPUs, privileged pods, cheap Spot capacity, EBS volumes, and EKS Pod Identity is NOT supported on
# Fargate -> use IRSA (09-irsa) for pod AWS access there. This is a favourite interview trap.
# NETWORKING: Fargate pods run ONLY in private subnets; each gets its own ENI and the cluster security group.
# COST: billed per pod vCPU/GB-second with a 1-minute minimum; $0 when no pods run. Create the profile freely, run pods briefly.
# DEPENDS ON: 05-iam (execution role), 06-eks, 01-vpc.  DEPENDED ON BY: kubernetes/serviceaccounts + the IRSA lab.
# GOES WRONG: pod stays Pending with "0/N nodes... " if its namespace/labels do not match a selector; CoreDNS must be able to run on EC2.
resource "aws_eks_fargate_profile" "demo" {
  cluster_name           = local.cluster_name
  fargate_profile_name   = "demo"
  pod_execution_role_arn = local.fargate_role_arn
  subnet_ids             = local.private_subnet_ids

  selector {
    namespace = var.fargate_namespace
  }
}
