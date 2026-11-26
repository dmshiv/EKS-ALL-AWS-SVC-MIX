variable "karpenter_version" {
  description = "Karpenter Helm chart version (v1 API: NodePool / EC2NodeClass). Must support your Kubernetes minor: https://karpenter.sh/docs/upgrading/compatibility/"
  type        = string
  default     = "1.14.1"
}

variable "controller_replicas" {
  description = "Karpenter controller replicas (leader elected). LAB=1 saves memory on small nodes; PRODUCTION=2."
  type        = number
  default     = 1
}
