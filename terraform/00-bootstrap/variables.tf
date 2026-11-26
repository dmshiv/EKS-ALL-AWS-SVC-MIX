variable "project" {
  description = "Project short name."
  type        = string
  default     = "cloudcart"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "lab"
}

variable "region" {
  description = "Region of the state bucket (all other folders must use the same region to read state)."
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Owner cost-allocation tag."
  type        = string
  default     = "CloudCart"
}

variable "budget_email" {
  description = "E-mail that receives AWS Budgets alerts. Empty string disables the budget."
  type        = string
  default     = ""
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget in USD. Alerts at 50%, 80% (actual) and 100% (forecast)."
  type        = number
  default     = 100
}
