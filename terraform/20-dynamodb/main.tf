# =============================================================================
# 20-dynamodb : product catalog
# =============================================================================
#
#   product-service Pod -> (Pod Identity creds) -> DynamoDB gateway endpoint (02, free) -> table
#
# WHY DYNAMODB FOR PRODUCTS: access is key-value ("get product p-1001", "list products in a category"), needs
# single-digit-ms latency and scales without connection pools or patching. The ORDER data uses PostgreSQL because
# orders are relational/transactional.  Rule of thumb: model DynamoDB around ACCESS PATTERNS, not around entities.
#
# ACCESS PATTERNS implemented
#   1. GetItem by product_id                 -> partition key (hash_key)
#   2. Query products by category            -> global secondary index "category-index"
#   3. Scan all (small demo catalog only)    -> avoid in production: it reads the whole table
#
# CAPACITY: PAY_PER_REQUEST (on-demand) = $1.25 per million writes / $0.25 per million reads, $0 when idle.
#   PROVISIONED + autoscaling is cheaper for steady, predictable traffic.
# SECURITY: IAM is the ONLY auth mechanism (no passwords, no network ACL on the table); encrypted at rest with our
#   CMK; point-in-time recovery (PITR) allows restore to any second in the last 35 days.

# WHY:        Product catalogue is key-value access by id: DynamoDB's partition key model fits and removes capacity management.
# DEPENDS:    Used by product-service; encrypted with the CMK; PITR enabled.
# GOES WRONG: Hot partition keys throttle first; PAY_PER_REQUEST avoids provisioning errors but costs more at steady high load.
resource "aws_dynamodb_table" "products" {
  name         = "${local.name}-products"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "product_id"

  attribute {
    name = "product_id"
    type = "S"
  }

  attribute {
    name = "category"
    type = "S"
  }

  global_secondary_index {
    name            = "category-index"
    hash_key        = "category"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = data.terraform_remote_state.kms.outputs.data_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = var.deletion_protection

  tags = { Name = "${local.name}-products" }
}

# Seed rows so the demo works immediately. In production, data is loaded by the application/migrations, not Terraform.
resource "aws_dynamodb_table_item" "seed" {
  for_each = var.seed_products

  table_name = aws_dynamodb_table.products.name
  hash_key   = aws_dynamodb_table.products.hash_key

  item = jsonencode({
    product_id = { S = each.key }
    name       = { S = each.value.name }
    price      = { N = tostring(each.value.price) }
    category   = { S = each.value.category }
  })
}
