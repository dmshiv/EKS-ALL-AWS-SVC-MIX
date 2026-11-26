# =============================================================================
# 29-alb : what Terraform owns around the Application Load Balancer
# =============================================================================
#
# THE ALB ITSELF IS NOT CREATED HERE. Request flow and ownership:
#
#   kubectl/Helm: Ingress object  --(watched by)-->  AWS Load Balancer Controller (28)  --elasticloadbalancing API-->
#   ALB (public subnets) + listeners + target group (target-type ip) + registers POD IPs as targets
#
#   Internet -> Route 53 -> CloudFront (32) -> WAF (33) -> ALB -> Target Group -> Pod IP:port -> Container
#
# WHY NOT TERRAFORM FOR THE ALB: the load balancer lifecycle must follow the Kubernetes Ingress (hosts, paths, health checks change with
# every deploy). If Terraform and the controller both managed it they would fight. Terraform owns the SUPPORTING resources the Ingress
# references by annotation: this ACCESS-LOG bucket, the WAF ACL (33), the certificate (27). See kubernetes/ingress/ingress.yaml.
#
# TARGET TYPES: ip (default here): the ALB sends traffic straight to Pod IPs (VPC CNI pods have real VPC IPs): one hop, per-pod health
#   checks, works on Fargate. instance: ALB -> NodePort -> kube-proxy -> pod: extra hop, double load balancing, hides client IP.
# HEALTH CHECKS: the target group probes /health on each pod; a pod failing its readiness probe is also removed (pod readiness gates).
# COMMON PRODUCTION FAILURES: Ingress ADDRESS stays empty (controller not running / no IAM permission / subnets untagged); 503 (no healthy
#   targets: wrong health-check path or security group blocks ALB -> pod); 502 (pod closes connection early); 504 (slow pod, idle timeout).
# COST: EXPENSIVE to forget: ~$0.0225/hour (~$16/month) per ALB + LCU. Delete the Ingress before destroying the cluster.
#
# ACCESS LOGS: every request (client IP, path, target, status, latency) to S3, the evidence for "who got a 5xx and why".
# ALB log buckets support SSE-S3 (AES256) only: SSE-KMS is NOT supported for ALB access logs.

data "aws_elb_service_account" "main" {
  count = var.use_legacy_elb_account ? 1 : 0
}

# WHY:        Access logs show who called the application and which target answered; they are essential for 5xx debugging.
# DEPENDS:    Used by the ALB created by the controller (log annotations).
# GOES WRONG: Logs accumulate cost; lifecycle below expires them.
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${local.name}-alb-logs-${local.account_id}-${var.region}"
  force_destroy = var.force_destroy
}

# WHY:        ALB log delivery supports SSE-S3 only (not KMS), so this bucket uses SSE-S3 deliberately.
# DEPENDS:    Depends on the bucket.
# GOES WRONG: Switching to KMS makes ALB log delivery silently fail.
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# WHY:        Logs contain client IPs and URLs: never public.
# DEPENDS:    Depends on the bucket.
# GOES WRONG: Without it a mistaken ACL/policy could expose the logs.
resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# WHY:        Bounds log storage cost.
# DEPENDS:    Depends on the bucket.
# GOES WRONG: No lifecycle = indefinite growth.
resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.log_retention_days
    }
  }
}

# RESOURCE POLICY: lets the ELB log-delivery principal write objects, and refuses plaintext transport.
data "aws_iam_policy_document" "alb_logs" {
  statement {
    sid       = "AllowAlbLogDelivery"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/${local.account_id}/*"]

    principals {
      type = var.use_legacy_elb_account ? "AWS" : "Service"
      identifiers = var.use_legacy_elb_account ? [data.aws_elb_service_account.main[0].arn] : [
        "logdelivery.elasticloadbalancing.amazonaws.com",
      ]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.alb_logs.arn, "${aws_s3_bucket.alb_logs.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# WHY:        Allows the regional ELB service principal to write logs to the bucket.
# DEPENDS:    Depends on the bucket; account/region-specific ELB principal.
# GOES WRONG: Wrong principal for the region: the load balancer reports 'Access Denied for bucket' and logs are never delivered.
resource "aws_s3_bucket_policy" "alb_logs" {
  bucket     = aws_s3_bucket.alb_logs.id
  policy     = data.aws_iam_policy_document.alb_logs.json
  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}
