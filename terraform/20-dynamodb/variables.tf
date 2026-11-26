variable "deletion_protection" {
  description = "PRODUCTION=true blocks table deletion (including terraform destroy). LAB=false."
  type        = bool
  default     = false
}

variable "seed_products" {
  description = "Sample catalog rows written by Terraform so the API has data immediately."
  type = map(object({
    name     = string
    price    = number
    category = string
  }))
  default = {
    "p-1001" = { name = "Wireless Mouse", price = 19.99, category = "accessories" }
    "p-1002" = { name = "Mechanical Keyboard", price = 79.5, category = "accessories" }
    "p-1003" = { name = "27-inch Monitor", price = 229.0, category = "displays" }
  }
}
