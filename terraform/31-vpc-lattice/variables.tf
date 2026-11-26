variable "enable_lattice" {
  description = "Create a VPC Lattice service network and associate this VPC. Services/targets are added later by the AWS Gateway API Controller (docs/networking)."
  type        = bool
  default     = false
}
