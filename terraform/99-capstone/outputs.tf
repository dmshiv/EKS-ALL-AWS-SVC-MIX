output "helm_values" {
  description = "Consolidated values for helm/cloudcart (scripts/deploy-app.sh consumes this as JSON)."
  value       = local.helm_values
}

output "architecture_summary" {
  description = "One-line view of the integrated platform for the interview walkthrough."
  value = {
    cluster      = local.out.eks.cluster_name
    registry     = local.registry
    ssm_prefix   = local.out.ssm.ssm_prefix
    dns_enabled  = local.out.dns.dns_enabled
    waf_acl      = local.out.waf.web_acl_name
    notifier     = local.out.lambda.lambda_function_name
    pod_identity = local.out.pod.role_arns
  }
}
