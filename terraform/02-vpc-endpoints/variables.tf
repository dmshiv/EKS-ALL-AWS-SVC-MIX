variable "enable_interface_endpoints" {
  description = "Create PrivateLink interface endpoints (billed per endpoint per AZ per hour). false = rely on the NAT gateway instead."
  type        = bool
  default     = true
}

variable "interface_endpoint_services" {
  description = "AWS services (suffix after com.amazonaws.<region>.) reached privately by pods/nodes."
  type        = list(string)
  default = [
    "ecr.api",        # ecr:GetAuthorizationToken, DescribeImages
    "ecr.dkr",        # docker registry API (image manifests)
    "sts",            # Pod Identity / IRSA credential exchange for workloads
    "ssm",            # Parameter Store (CloudCart reads its config here)
    "secretsmanager", # DB credentials
    "sqs",            # order queue
    "events",         # worker publishes order events to EventBridge
  ]
}

variable "interface_endpoint_az_count" {
  description = "In how many AZs to place endpoint ENIs. LAB=1 (cheap). PRODUCTION=all AZs (HA, no cross-AZ traffic)."
  type        = number
  default     = 1

  validation {
    condition     = var.interface_endpoint_az_count >= 1 && var.interface_endpoint_az_count <= 3
    error_message = "interface_endpoint_az_count must be 1..3."
  }
}
