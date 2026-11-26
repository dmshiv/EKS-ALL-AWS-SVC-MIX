variable "enable_cloudfront" {
  description = "Create the distribution. Requires a domain (26-route53) and a deployed Ingress whose ALB hostname is published as origin.<domain>."
  type        = bool
  default     = false
}

variable "price_class" {
  description = "PriceClass_100 = US/Canada/Europe edges only (cheapest)."
  type        = string
  default     = "PriceClass_100"
}
