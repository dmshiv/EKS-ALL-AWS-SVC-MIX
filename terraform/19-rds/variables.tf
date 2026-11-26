variable "instance_class" {
  description = "RDS instance class. LAB: db.t4g.micro (Graviton burstable)."
  type        = string
  default     = "db.t4g.micro"
}

variable "engine_version" {
  description = "PostgreSQL major version (minor upgrades are applied automatically)."
  type        = string
  default     = "16"
}

variable "allocated_storage_gb" {
  description = "Initial storage (GiB, gp3)."
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "PRODUCTION=true: synchronous standby in another AZ with automatic failover (2x cost). LAB=false."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Automated backup retention (point-in-time recovery window). 0 disables backups."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "PRODUCTION=true. LAB=false so terraform destroy works."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "DESTRUCTIVE: LAB=true deletes the database without a final snapshot. PRODUCTION=false."
  type        = bool
  default     = true
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "cloudcart"
}
