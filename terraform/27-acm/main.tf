# =============================================================================
# 27-acm : TLS certificates (OPTIONAL: needs the domain from 26-route53)
# =============================================================================
#
#   ACM wildcard cert *.<domain>
#     - regional copy  -> attached to the ALB HTTPS listener (TLS terminates at the ALB)
#     - us-east-1 copy -> attached to CloudFront (only a separate cert when the stack is NOT in us-east-1)
#
# ACM DNS VALIDATION (how a certificate is issued): ACM gives a CNAME (_xyz.<domain> -> _abc.acm-validations.aws). We create it in the zone;
# ACM polls DNS, sees it, proves you control the domain, issues the cert, and RENEWS it automatically as long as that CNAME stays.
# aws_acm_certificate_validation makes Terraform WAIT until the status is ISSUED (no sleep guessing).
# COMMON FAILURES: zone not delegated => validation hangs "Pending validation" forever; validation CNAME deleted => renewal fails
#   silently weeks later; cert in the wrong region for the service (CloudFront needs us-east-1, ALB needs its own region).
# TLS TERMINATION: the ALB/CloudFront decrypt HTTPS; traffic ALB -> pod is HTTP inside the VPC (or re-encrypt for strict compliance).
# COST: ACM public certificates are FREE.

# WHY:        ALBs terminate TLS with a certificate from ACM in the SAME region as the load balancer.
# DEPENDS:    Used by 29-alb / the Ingress annotation.
# GOES WRONG: Stays PENDING_VALIDATION forever if the validation CNAME is not published in the correct public zone.
resource "aws_acm_certificate" "regional" {
  count = local.enabled ? 1 : 0

  domain_name       = "*.${local.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# WHY:        DNS validation proves domain ownership and enables automatic renewal (no manual steps every year).
# DEPENDS:    Depends on the certificate and the hosted zone.
# GOES WRONG: Records in a private zone or a zone whose NS are not delegated at the registrar never validate.
resource "aws_route53_record" "validation" {
  for_each = local.enabled ? {
    for dvo in aws_acm_certificate.regional[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id         = local.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# WHY:        Makes Terraform WAIT until the certificate is ISSUED; this is the 'no sleep' dependency for everything that uses the certificate.
# DEPENDS:    Depends on the certificate and validation records.
# GOES WRONG: Plan/apply hangs: that means validation is not completing, not that Terraform is slow.
resource "aws_acm_certificate_validation" "regional" {
  count = local.enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.regional[0].arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

# WHY:        CloudFront only accepts certificates from us-east-1.
# DEPENDS:    Used by 32-cloudfront; created through the us_east_1 provider alias.
# GOES WRONG: A certificate created in the wrong region is invisible to CloudFront.
resource "aws_acm_certificate" "global" {
  count    = local.need_global_cert ? 1 : 0
  provider = aws.us_east_1

  domain_name       = "*.${local.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# The validation CNAME for the same wildcard is identical in both regions, so the record created above is reused.
resource "aws_acm_certificate_validation" "global" {
  count    = local.need_global_cert ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.global[0].arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}
