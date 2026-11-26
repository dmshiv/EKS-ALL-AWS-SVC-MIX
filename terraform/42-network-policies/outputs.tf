output "baseline_policy" {
  description = "Baseline NetworkPolicy applied to the application namespace."
  value       = "${kubernetes_network_policy_v1.default_deny_ingress.metadata[0].namespace}/${kubernetes_network_policy_v1.default_deny_ingress.metadata[0].name}"
}
