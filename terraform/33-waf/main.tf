# =============================================================================
# 33-waf : AWS WAF (REGIONAL web ACL for the Application Load Balancer)
# =============================================================================
#
#   Internet -> CloudFront (32) -> [ WAF web ACL ] -> ALB -> Kubernetes Service -> Pod
#                                      ^ attached to the ALB by the Ingress annotation alb.ingress.kubernetes.io/wafv2-acl-arn
#
# WHAT WAF PROTECTS: layer-7 attacks on HTTP(S): SQL injection, XSS, known-bad inputs, abusive clients (rate limiting). It does NOT replace
#   input validation in the app, IAM, security groups or NetworkPolicies, and it cannot see traffic that bypasses the ALB.
# WHY REGIONAL: WAF attaches to the ALB (regional resource). The ALB is created by the AWS Load Balancer Controller from the Ingress, so
#   Terraform cannot attach the ACL; the Ingress annotation does it, and the ACL ARN is this folder's output.
# RULE ORDER: lower priority number is evaluated first. Rate limit first (cheap), then AWS managed rule groups.
# ROLLOUT PRACTICE: start with managed_rules_action="count" (log only), review sampled requests, then enforce. A blocked legitimate request
#   is an outage you caused.
# COST: EXPENSIVE-ish: $5/month per web ACL + $1/month per rule (each managed rule group = 1 rule) + $0.60 per million requests inspected.
#   A lab ACL with 4 rules is ~ $9/month plus traffic: destroy it after the lab.
# LIMITS/GOTCHAS: body inspection is limited to the first 8 KB (ALB) ; managed rules can false-positive on legitimate JSON.
# DEPENDS ON: nothing. DEPENDED ON BY: kubernetes/ingress (annotation) via the output.

locals {
  # AWS managed rule groups: name => priority. Maintained by AWS, updated automatically.
  managed_groups = {
    AWSManagedRulesCommonRuleSet          = 10 # OWASP-style generic protections
    AWSManagedRulesKnownBadInputsRuleSet  = 20 # exploit patterns (e.g. Log4j)
    AWSManagedRulesSQLiRuleSet            = 30 # SQL injection
    AWSManagedRulesAmazonIpReputationList = 40 # IPs AWS threat intel flags
  }
}

# WHY:        Filters malicious HTTP at the edge of the application: AWS managed rule groups plus a rate limit.
# DEPENDS:    Associated with the ALB; REGIONAL scope (CloudFront would need CLOUDFRONT scope in us-east-1).
# GOES WRONG: Rule in block mode on day one can block real users: start in COUNT and review samples.
resource "aws_wafv2_web_acl" "alb" {
  name        = "${local.name}-alb"
  description = "CloudCart ALB protection"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit-per-ip"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit_per_5min
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-per-ip"
      sampled_requests_enabled   = true
    }
  }

  dynamic "rule" {
    for_each = local.managed_groups

    content {
      name     = rule.key
      priority = rule.value

      # override_action: "none" = apply the group's own actions (block); "count" = observe only.
      override_action {
        dynamic "none" {
          for_each = var.managed_rules_action == "none" ? [1] : []
          content {}
        }

        dynamic "count" {
          for_each = var.managed_rules_action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = rule.key
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.key
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-alb"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${local.name}-alb" }
}

# WAF LOGS: the log group name MUST start with "aws-waf-logs-" or WAF refuses it. Logs show which rule blocked which request
# (the first thing to read when a user reports a 403).
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${local.name}"
  retention_in_days = var.log_retention_days
}

# WHY:        Without logs you cannot tell which rule blocked a request.
# DEPENDS:    Depends on the web ACL and the log group (name must start with aws-waf-logs-).
# GOES WRONG: Wrong log group name prefix -> association fails.
resource "aws_wafv2_web_acl_logging_configuration" "alb" {
  resource_arn            = aws_wafv2_web_acl.alb.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
}
