# =============================================================================
# 26-route53 : DNS (hosted zone) + ExternalDNS   (OPTIONAL: needs a domain you control)
# =============================================================================
#
#   user --DNS--> Route 53 public hosted zone
#                   cloudcart.<domain>  --ALIAS--> CloudFront (32)           (or the ALB when CloudFront is off)
#                   origin.<domain>     --ALIAS--> ALB   (written by ExternalDNS from the Ingress host annotation)
#
# DNS FAILURE MODES (interview): zone not delegated (registrar NS != the zone's NS) => nothing resolves and ACM validation hangs;
#   record points at a deleted ALB (dangling); TTL too high during a cutover; wrong record type (CNAME at the zone apex is illegal:
#   use ALIAS records, which are free and follow the AWS resource's IPs).
# WHY EXTERNALDNS: an Ingress creates an ALB with a random hostname. ExternalDNS watches Ingress hosts and writes the Route 53 records,
#   so DNS follows the Kubernetes objects and is cleaned up with them.
# COST: hosted zone $0.50/month, queries $0.40/million. Registering a domain is separate (~$10+/year).
# DEPENDS ON: 06-eks, nodes (10), Pod Identity agent (06). DEPENDED ON BY: 27-acm (validation records), 32-cloudfront (alias).

locals {
  enabled     = var.domain_name != ""
  app_fqdn    = local.enabled ? "${var.app_subdomain}.${var.domain_name}" : ""
  origin_fqdn = local.enabled ? "${var.origin_subdomain}.${var.domain_name}" : ""
}

# true => we own a brand-new zone: you MUST then delegate its NS records at your registrar (output name_servers).
resource "aws_route53_zone" "this" {
  count = local.enabled && var.create_hosted_zone ? 1 : 0

  name    = var.domain_name
  comment = "CloudCart ${var.environment}"
}

data "aws_route53_zone" "existing" {
  count = local.enabled && !var.create_hosted_zone ? 1 : 0

  name         = var.domain_name
  private_zone = false
}

locals {
  zone_id = !local.enabled ? "" : (var.create_hosted_zone ? aws_route53_zone.this[0].zone_id : data.aws_route53_zone.existing[0].zone_id)
}

# ---------------------------------------------------------------------------------------------
# EXTERNALDNS (Pod Identity)
# ---------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# Least privilege: change records ONLY in our zone; the list calls cannot be scoped to a zone.
data "aws_iam_policy_document" "external_dns" {
  count = local.enabled ? 1 : 0

  statement {
    sid       = "ChangeRecordsInOurZone"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:${local.partition}:route53:::hostedzone/${local.zone_id}"]
  }

  statement {
    sid       = "ListZonesAndRecords"
    actions   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResources"]
    resources = ["*"]
  }
}

# WHY:        ExternalDNS creates records for Ingress hosts automatically; it needs Route 53 write access, not the pods.
# DEPENDS:    Trusted via Pod Identity; used by the external-dns ServiceAccount.
# GOES WRONG: No records appear and the controller logs 'AccessDenied: route53:ChangeResourceRecordSets'.
resource "aws_iam_role" "external_dns" {
  count = local.enabled ? 1 : 0

  name               = "${local.name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

# WHY:        Scoped to the one hosted zone so a bug cannot rewrite other zones.
# DEPENDS:    Depends on the hosted zone ARN.
# GOES WRONG: A wildcard zone resource would let a compromised pod hijack any domain you own.
resource "aws_iam_role_policy" "external_dns" {
  count = local.enabled ? 1 : 0

  name   = "route53-our-zone"
  role   = aws_iam_role.external_dns[0].id
  policy = data.aws_iam_policy_document.external_dns[0].json
}

# WHY:        Maps the role to the external-dns ServiceAccount.
# DEPENDS:    Depends on the cluster and the Pod Identity agent.
# GOES WRONG: Wrong namespace/name = silent fallback to the node role (AccessDenied).
resource "aws_eks_pod_identity_association" "external_dns" {
  count = local.enabled ? 1 : 0

  cluster_name    = local.eks.cluster_name
  namespace       = "kube-system"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns[0].arn
}

# policy=upsert-only: ExternalDNS may create/update records but never delete ones it did not make (safer in a shared zone).
# txtOwnerId marks the records it owns so two clusters never fight over a name.
resource "helm_release" "external_dns" {
  count = local.enabled ? 1 : 0

  name       = "external-dns"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = var.external_dns_chart_version
  timeout    = 300
  wait       = true

  values = [yamlencode({
    provider       = { name = "aws" }
    sources        = ["ingress"]
    domainFilters  = [var.domain_name]
    policy         = "upsert-only"
    registry       = "txt"
    txtOwnerId     = local.eks.cluster_name
    serviceAccount = { create = true, name = "external-dns" }
    env            = [{ name = "AWS_DEFAULT_REGION", value = var.region }]
  })]

  depends_on = [aws_eks_pod_identity_association.external_dns, aws_iam_role_policy.external_dns]
}
