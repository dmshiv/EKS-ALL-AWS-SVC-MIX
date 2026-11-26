# =============================================================================
# 32-cloudfront : global edge in front of the ALB (OPTIONAL)
# =============================================================================
#
#   user --> Route 53 ALIAS cloudcart.<domain> --> CloudFront edge (TLS, cache, WAF) --HTTPS--> origin.<domain> --> ALB --> Pods
#
# WHY CLOUDFRONT: TLS terminates near the user (lower latency), static assets are cached at the edge (less load on pods/ALB), a global
# WAF ACL and AWS Shield Standard protect the entry point, and the ALB can be locked down so only CloudFront reaches it.
# CACHING POLICY choices below: dynamic API traffic = CachingDisabled (always hits the origin); /static/* = CachingOptimized.
# COST: no hourly fee; $0.085/GB egress (first 1 TB/month free tier) + $0.0075-0.012 per 10k HTTPS requests. Cheap for a lab.
# WAF PLACEMENT: the web ACL (33-waf) is REGIONAL and attached to the ALB, matching the flow CloudFront -> WAF -> ALB.
# GOES WRONG: 502/504 from CloudFront = origin unreachable/slow or TLS mismatch (origin cert must cover the origin hostname);
#   stale content = cached object (invalidate with aws cloudfront create-invalidation); 403 = WAF block or missing alias/cert.
#
# ORIGIN LOCK-DOWN (production): add a secret custom header here and require it on the ALB listener rule, or allow only the managed prefix list
#   com.amazonaws.global.cloudfront.origin-facing in the ALB security group, so users cannot bypass CloudFront/WAF by hitting the ALB directly.

locals {
  # AWS managed policy ids (stable, documented constants).
  cache_policy_disabled  = "4135ea2d-6df8-44a3-9df3-4b5a8de9b0f0" # Managed-CachingDisabled
  cache_policy_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
  origin_request_all     = "216adef6-5c7f-47e4-b989-5492eafa07d3" # Managed-AllViewer (forwards Host, query, cookies, headers)
}

# WHY:        Global edge cache + TLS front door in front of the ALB (WAF itself is attached to the ALB in 33-waf).
# DEPENDS:    Depends on the ALB origin, the us-east-1 certificate (27-acm).
# GOES WRONG: Takes minutes to deploy; 502/504 usually means the origin TLS/host header or security group blocks CloudFront.
resource "aws_cloudfront_distribution" "this" {
  count = local.enabled ? 1 : 0

  enabled         = true
  is_ipv6_enabled = true
  comment         = "CloudCart ${var.environment}"
  aliases         = [local.dns.app_fqdn]
  price_class     = var.price_class

  origin {
    domain_name = local.dns.origin_fqdn
    origin_id   = "alb"

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 30
      origin_keepalive_timeout = 5
    }
  }

  default_cache_behavior {
    target_origin_id         = "alb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_policy_disabled
    origin_request_policy_id = local.origin_request_all
    compress                 = true
  }

  ordered_cache_behavior {
    path_pattern             = "/static/*"
    target_origin_id         = "alb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_policy_optimized
    origin_request_policy_id = local.origin_request_all
    compress                 = true
  }

  viewer_certificate {
    acm_certificate_arn      = local.acm.cloudfront_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = { Name = "${local.name}-cdn" }
}

# ALIAS (not CNAME) records to CloudFront: free queries, works at the zone apex, resolves to CloudFront's anycast IPs.
resource "aws_route53_record" "app_a" {
  count = local.enabled ? 1 : 0

  zone_id = local.dns.zone_id
  name    = local.dns.app_fqdn
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this[0].domain_name
    zone_id                = aws_cloudfront_distribution.this[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# WHY:        IPv6 alias to the distribution so IPv6 clients resolve it.
# DEPENDS:    Depends on the distribution and hosted zone.
# GOES WRONG: Missing AAAA is harmless but hides IPv6 issues until a client hits them.
resource "aws_route53_record" "app_aaaa" {
  count = local.enabled ? 1 : 0

  zone_id = local.dns.zone_id
  name    = local.dns.app_fqdn
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.this[0].domain_name
    zone_id                = aws_cloudfront_distribution.this[0].hosted_zone_id
    evaluate_target_health = false
  }
}
