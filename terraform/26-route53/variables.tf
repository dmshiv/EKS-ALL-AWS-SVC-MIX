variable "domain_name" {
  description = "Root domain you control (e.g. example.com). EMPTY = DNS/TLS disabled; the app is reachable on the raw ALB hostname over HTTP."
  type        = string
  default     = ""
}

variable "create_hosted_zone" {
  description = "true = create a NEW public hosted zone (then delegate the NS records at your registrar). false = use an existing zone for domain_name."
  type        = bool
  default     = false
}

variable "app_subdomain" {
  description = "Public hostname users visit: <app_subdomain>.<domain_name> (CloudFront alias if enabled, otherwise the ALB)."
  type        = string
  default     = "cloudcart"
}

variable "origin_subdomain" {
  description = "Hostname of the ALB that CloudFront uses as origin: <origin_subdomain>.<domain_name>."
  type        = string
  default     = "origin"
}

variable "external_dns_chart_version" {
  description = "external-dns Helm chart version (kubernetes-sigs/external-dns)."
  type        = string
  default     = "1.23.0"
}
