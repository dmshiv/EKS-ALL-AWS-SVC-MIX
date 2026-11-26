# =============================================================================
# 28-load-balancer-controller : AWS Load Balancer Controller (turns Ingress/Service into ALB/NLB)
# =============================================================================
#
#   kubectl apply Ingress --> controller (watches API) --> elasticloadbalancing:CreateLoadBalancer / CreateTargetGroup / ...
#
#   Internet --> Route 53 --> [ALB in PUBLIC subnets] --> Target Group --> Pod IPs (target-type: ip) --> container
#                                  ^ found through the subnet tag kubernetes.io/role/elb=1 (01-vpc)
#
# THE LOAD BALANCER IS NOT PART OF EKS. Kubernetes only knows "Ingress". This controller (a pod you install) calls the AWS ELB API.
# Without it: an Ingress object just sits there with an empty ADDRESS.
#
# TARGET TYPES (key interview topic)
#   ip       : ALB sends traffic DIRECTLY to Pod IPs (possible because VPC CNI pods have real VPC IPs). One hop, health checks per
#              pod, works with Fargate. DEFAULT in this project.
#   instance : ALB -> NodePort on a node -> kube-proxy -> pod. Extra hop, double load balancing, SNAT hides client IP.
# Ingress -> ALB (L7, HTTP/HTTPS, host/path routing, WAF, OIDC auth).   Service type=LoadBalancer -> NLB (L4, TCP/TLS, static IPs).
#
# COST: every ALB/NLB ~ $0.0225/h (~$16/month) + LCU usage. EXPENSIVE to forget. Ingresses must be DELETED before destroying the cluster
# or the ALBs/target groups/SGs are orphaned in AWS and block VPC deletion (see scripts/destroy-all.sh).

# IAM POLICY = the official policy from kubernetes-sigs/aws-load-balancer-controller (iam_policy.json, kept verbatim and pinned in Git).
# Re-download it when upgrading the controller: the controller's required permissions change between releases.
resource "aws_iam_policy" "lbc" {
  name        = "${local.name}-aws-load-balancer-controller"
  description = "Permissions for the AWS Load Balancer Controller"
  policy      = file("${path.module}/iam_policy.json")
}

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# WHY:        The controller calls EC2/ELB APIs to build ALBs and target groups from Ingress objects.
# DEPENDS:    Trusted via Pod Identity; used by the aws-load-balancer-controller ServiceAccount.
# GOES WRONG: Ingress has no ADDRESS and the controller log shows AccessDenied or 'no subnets with kubernetes.io/role/elb tag'.
resource "aws_iam_role" "lbc" {
  name               = "${local.name}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

# WHY:        Attaches the official LBC IAM policy.
# DEPENDS:    Depends on the lbc role.
# GOES WRONG: An outdated policy lacks new actions and fails on newer controller versions.
resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

# Binds kube-system/aws-load-balancer-controller -> role. Must exist BEFORE the pods start (hence depends_on in the release).
resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = local.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc.arn
}

# region + vpcId are set explicitly: pods cannot reach the instance metadata service (IMDSv2 hop limit 1 on EKS nodes), and the
# controller otherwise tries to discover them there (symptom: "failed to get VPC ID from instance metadata").
resource "helm_release" "lbc" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  timeout    = 600
  wait       = true

  values = [yamlencode({
    clusterName  = local.eks.cluster_name
    region       = var.region
    vpcId        = local.vpc_id
    replicaCount = var.replica_count

    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
    }

    controllerConfig = {
      featureGates = var.enable_gateway_api ? tomap({
        ALBGatewayAPI = true
        NLBGatewayAPI = true
      }) : tomap({})
    }

    # Spread replicas over nodes so one node failure does not stop reconciliation.
    topologySpreadConstraints = [{
      maxSkew           = 1
      topologyKey       = "kubernetes.io/hostname"
      whenUnsatisfiable = "ScheduleAnyway"
      labelSelector = {
        matchLabels = {
          "app.kubernetes.io/name" = "aws-load-balancer-controller"
        }
      }
    }]
  })]

  depends_on = [
    aws_eks_pod_identity_association.lbc,
    aws_iam_role_policy_attachment.lbc,
  ]
}
