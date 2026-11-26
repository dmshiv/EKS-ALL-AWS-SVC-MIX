# =============================================================================
# 42-network-policies : platform BASELINE for pod-to-pod traffic
# =============================================================================
#
# THE FOUR FIREWALLS (the interview cheat-sheet: where each one operates)
#   AWS IAM            : may you call this AWS API?                       evaluated by AWS, per request, on identity
#   Security Group     : may this ENI accept this packet?                 enforced by the VPC on node/branch ENIs, by IP/SG (not labels)
#   NetworkPolicy      : may pod A talk to pod B?                         enforced on the NODE by the CNI (eBPF in the VPC CNI), by LABELS
#   Kubernetes RBAC    : may this user/ServiceAccount call this K8s API?  evaluated by the API server
# They stack; none replaces another. A NetworkPolicy cannot stop a pod calling S3 (that is IAM + SG + endpoint policy).
#
# HOW ENFORCEMENT WORKS HERE: enableNetworkPolicy=true on the VPC CNI add-on (06-eks) runs the network policy agent on every node;
# it translates NetworkPolicy objects into eBPF programs on the pod's veth. Without that flag the objects are accepted and SILENTLY IGNORED
# (a favourite interview and production trap). Kubernetes NetworkPolicy is ADDITIVE: no policy selecting a pod = everything allowed; once ANY
# policy selects a pod for ingress, only what the policies allow is permitted.
#
# WHAT TERRAFORM OWNS vs WHAT HELM OWNS: this folder owns the cluster-wide default (deny all ingress in the application namespace), a
# guardrail the platform team controls. The ALLOW rules belong to each service (helm/cloudcart templates and kubernetes/network-policies/)
# because they change with the application.
# PREREQUISITE: the namespace must exist. The data source below FAILS FAST at plan time with a clear error if it does not.
# GOES WRONG: after applying, pods that previously talked to each other get "connection timed out" until the allow policies from Helm exist.
# That is the point of default-deny, and a good controlled failure for USER_GUIDE section 27.
# COST: none.

data "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.namespace
  }
}

# WHY:        Platform guardrail: every pod in the namespace starts with NO inbound traffic; services add allow rules.
# DEPENDS:    Depends on the namespace; relies on enableNetworkPolicy in the VPC CNI (06-eks).
# GOES WRONG: Applying it before the allow policies exist causes 'connection timed out' between pods: intentional, and a good failure test.
resource "kubernetes_network_policy_v1" "default_deny_ingress" {
  metadata {
    name      = "default-deny-ingress"
    namespace = data.kubernetes_namespace_v1.app.metadata[0].name
  }

  spec {
    # empty podSelector = every pod in the namespace
    pod_selector {}

    policy_types = ["Ingress"]
  }
}
