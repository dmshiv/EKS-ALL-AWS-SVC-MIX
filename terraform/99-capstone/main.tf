# =============================================================================
# 99-capstone : the integration point (creates NO AWS resources)
# =============================================================================
#
#   INTERNET
#      |
#   Route 53 (26) --> CloudFront (32) --> WAF (33) --> ALB (created by Ingress, 28/29) --> Kubernetes Service --> Pod
#                                                                |
#      +---------------------- EKS (06) ------------------------+----------------------+
#      |  frontend       product-service        order-service          worker           |
#      +-------------------+---------+-------------+------+-----------+----------------+
#                          |         |             |      |           |
#                       DynamoDB(20) S3(15)   RDS(19) Redis(21)   SQS(22) --> worker --> EventBridge(24) --> Lambda(25) --> SNS(23)
#
#   around it: IAM(05) Pod Identity(08) IRSA(09) KMS(16) Secrets Manager(17) Parameter Store(18) ECR(04) VPC(01,02) Security Groups(03,43)
#              NetworkPolicies(42) CloudWatch(34,35) CloudTrail(36) GuardDuty(37) Security Hub(38) Config(39) Karpenter(12) Backup(40)
#
# WHAT THIS FOLDER DOES
#   1. Reads the state of every layer that the APPLICATION deployment needs and publishes ONE consolidated value set (helm_values) that
#      scripts/deploy-app.sh feeds to Helm. No AWS ID is ever copied by hand into YAML.
#   2. Declares `check` blocks: integration assertions evaluated at plan/apply time that WARN (never fail the run) when two layers disagree,
#      e.g. DNS enabled but no certificate, or the Pod Identity namespace differing from the namespace the chart deploys into.
# WHY: separate folders mean separate states; the capstone is the single place where the whole platform is seen together.
# COST: none.

check "dns_requires_certificate" {
  assert {
    condition     = !local.out.dns.dns_enabled || local.out.acm.alb_certificate_arn != ""
    error_message = "A domain is configured (26-route53) but 27-acm produced no ALB certificate. Apply 27-acm before exposing the Ingress over HTTPS."
  }
}

check "pod_identity_namespace_matches_chart" {
  assert {
    condition     = local.out.pod.namespace == var.app_namespace
    error_message = "08-pod-identity associations are bound to namespace '${local.out.pod.namespace}' but the chart deploys into '${var.app_namespace}'. Pods would get NO AWS credentials."
  }
}

check "images_repositories_exist" {
  assert {
    condition     = length(local.out.ecr.repository_urls) == 4
    error_message = "Expected 4 ECR repositories (frontend, product-service, order-service, worker)."
  }
}

locals {
  registry = local.out.ecr.registry_url

  # Everything the Helm chart needs that is NOT already discovered at runtime from Parameter Store.
  helm_values = {
    global = {
      region            = var.region
      clusterName       = local.out.eks.cluster_name
      ssmPrefix         = local.out.ssm.ssm_prefix
      vpcCidr           = local.out.vpc.vpc_cidr
      imageRegistry     = local.registry
      imageTag          = var.image_tag
      domain            = local.out.dns.app_fqdn
      originDomain      = local.out.dns.origin_fqdn
      albCertificateArn = local.out.acm.alb_certificate_arn
      wafAclArn         = local.out.waf.web_acl_arn
      accessLogsBucket  = local.out.albl.access_logs_bucket
      efsFileSystemId   = local.out.efs.efs_file_system_id
      efsAccessPointId  = local.out.efs.efs_access_point_id
      nlbEipAllocations = local.out.nlb.eip_allocation_ids
      nlbSubnetIds      = join(",", local.out.nlb.public_subnet_ids)
      irsaDemoRoleArn   = local.out.irsa.irsa_demo_role_arn
    }
  }
}
