variable "engine" {
  description = "valkey (AWS-recommended, cheaper, wire-compatible with Redis clients) or redis."
  type        = string
  default     = "valkey"

  validation {
    condition     = contains(["valkey", "redis"], var.engine)
    error_message = "engine must be valkey or redis."
  }
}

variable "node_type" {
  description = "Cache node type. LAB: cache.t4g.micro."
  type        = string
  default     = "cache.t4g.micro"
}

variable "num_cache_clusters" {
  description = "Nodes in the replication group (1 primary + N-1 replicas). LAB=1. PRODUCTION>=2 with automatic failover across AZs."
  type        = number
  default     = 1
}

variable "snapshot_retention_days" {
  description = "Daily snapshot retention. A cache is rebuildable, so LAB=0."
  type        = number
  default     = 0
}
