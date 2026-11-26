variable "chart_version" {
  description = "aws-load-balancer-controller Helm chart version (eks-charts repo). Pin it; controller upgrades can change ALB behaviour."
  type        = string
  default     = "3.5.0"
}

variable "replica_count" {
  description = "Controller replicas (leader-elected). LAB=2 for rolling updates; PRODUCTION=2+ spread across AZs."
  type        = number
  default     = 2
}

variable "enable_gateway_api" {
  description = "Turn on the controller's Gateway API feature gates (ALBGatewayAPI/NLBGatewayAPI). Requires the Gateway API CRDs installed first (see docs/networking)."
  type        = bool
  default     = false
}
