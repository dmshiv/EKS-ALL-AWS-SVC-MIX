variable "enable_argocd" {
  description = "Install Argo CD (GitOps controller) into the cluster. It adds ~7 pods of load; LAB default false."
  type        = bool
  default     = false
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version (argoproj/argo-helm)."
  type        = string
  default     = "10.9.6"
}
