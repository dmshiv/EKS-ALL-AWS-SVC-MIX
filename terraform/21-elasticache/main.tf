# =============================================================================
# 21-elasticache : cache for the product catalog (Valkey/Redis)
# =============================================================================
#
#   product-service --GET /products/{id}--> cache hit?  yes -> return (sub-millisecond)
#                                                         no  -> DynamoDB -> store in cache with TTL -> return
#
# WHY A CACHE: DynamoDB is already fast, but a cache cuts read cost and tail latency for hot items and shows the pattern. The app must
# treat the cache as OPTIONAL: if the cache is down the API still works (slower). This "fail open" behaviour is implemented in
# application/services/product-service and tested in USER_GUIDE section 17.
# NETWORK: cache nodes live in isolated database subnets; the redis SG allows 6379 only from node-sg (03).
# SECURITY: encryption in transit (TLS; clients use rediss://) + AUTH token (from Secrets Manager, 17) + encryption at rest (CMK).
# CACHE FAILURE BEHAVIOUR: node failure with 1 node = cache empty and unavailable until it is replaced (acceptable: it is a cache);
#   with replicas + automatic failover a replica is promoted. Cold cache = DynamoDB load spike: watch for it.
# COST: EXPENSIVE-ish and 24/7: cache.t4g.micro ~ $12/month per node. Destroy after the lab.
# ALTERNATIVES: DAX (DynamoDB-only cache), in-process cache (no shared state), MemoryDB (durable Redis, higher price).

locals {
  engine_version  = var.engine == "valkey" ? "8.0" : "7.1"
  parameter_group = var.engine == "valkey" ? "default.valkey8" : "default.redis7"
}

# WHY:        Places the Redis nodes in the isolated database subnets.
# DEPENDS:    Depends on 01-vpc; used by the replication group.
# GOES WRONG: Subnets in one AZ only means no automatic failover target.
resource "aws_elasticache_subnet_group" "this" {
  name       = "${local.name}-cache"
  subnet_ids = data.terraform_remote_state.vpc.outputs.database_subnet_ids

  tags = { Name = "${local.name}-cache" }
}

# The AUTH token comes from 17-secrets-manager (generated there, stored in the secret the pods read).
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${local.name}-cache"
  description          = "CloudCart product cache"

  engine               = var.engine
  engine_version       = local.engine_version
  node_type            = var.node_type
  port                 = 6379
  parameter_group_name = local.parameter_group

  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = var.num_cache_clusters > 1
  multi_az_enabled           = var.num_cache_clusters > 1

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [data.terraform_remote_state.sg.outputs.redis_security_group_id]

  at_rest_encryption_enabled = true
  kms_key_id                 = data.terraform_remote_state.kms.outputs.data_key_arn
  transit_encryption_enabled = true
  auth_token                 = data.terraform_remote_state.secrets.outputs.redis_auth_token

  snapshot_retention_limit = var.snapshot_retention_days
  apply_immediately        = true

  tags = { Name = "${local.name}-cache" }
}

# Config publication (see 18-parameter-store).
resource "aws_ssm_parameter" "config" {
  for_each = {
    "redis/host" = aws_elasticache_replication_group.this.primary_endpoint_address
    "redis/port" = tostring(aws_elasticache_replication_group.this.port)
  }

  name  = "${local.ssm_prefix}/${each.key}"
  type  = "String"
  value = each.value
}
