# =============================================================================
# 19-rds : PostgreSQL for orders
# =============================================================================
#
#   order-service Pod --tcp/5432--> node ENI --> [RDS SG: allow from node-sg (03)] --> RDS in an ISOLATED database subnet
#          |
#          +--(Pod Identity)--> secretsmanager:GetSecretValue (17) --> {username,password}   (no password in Git/env/Helm)
#
# WHY RDS (not a PostgreSQL pod): backups, patching, failover, encryption and monitoring are managed. Databases in Kubernetes need
# StatefulSets, EBS volume care and an operator; fine for dev, rarely the right call for order data.
# RDS vs AURORA: Aurora separates compute from a 6-way replicated storage layer (faster failover and replicas, higher cost, I/O pricing
# quirks). Plain RDS PostgreSQL is cheaper for small steady workloads; choose Aurora for many read replicas, <30s failover or very
# large storage. See docs/decisions/adr-rds-vs-aurora.md.
#
# NETWORK: subnet group = isolated database subnets (no route to the internet). Reachability = routing inside the VPC (always present)
#   AND the RDS security group allowing 5432 from node-sg. These are the TWO conditions for a pod to connect (Phase 0 question).
# BACKUPS: automated daily snapshots + transaction logs => point-in-time restore inside the retention window; final snapshot on delete.
# CONNECTION POOLING: every pod holds connections; N replicas x pool size must stay below max_connections. Use a small pool per pod
#   (the app does) and RDS Proxy in production.
# FAILURE SCENARIOS: instance failure (Multi-AZ fails over in ~60-120s; single-AZ restores from backup), AZ outage, wrong SG (timeouts),
#   password drift after rotation (re-read the secret), connection exhaustion (pods CrashLoop with "too many clients").
# COST: EXPENSIVE-ish and 24/7: db.t4g.micro ~ $12/month + gp3 storage. Multi-AZ doubles it. Prefer destroy for labs.

# WHY:        RDS can only be placed in subnets you list here; we use the isolated database subnets across AZs for Multi-AZ.
# DEPENDS:    Depends on 01-vpc database subnet IDs; used by the DB instance.
# GOES WRONG: Fewer than two AZs makes Multi-AZ impossible; changing the group on a running instance is disruptive.
resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-db"
  subnet_ids = local.out.vpc.database_subnet_ids

  tags = { Name = "${local.name}-db" }
}

# rds.force_ssl=1: the server rejects non-TLS connections (clients must use sslmode=require or stronger).
resource "aws_db_parameter_group" "this" {
  name_prefix = "${local.name}-pg-"
  family      = "postgres${var.engine_version}"
  description = "CloudCart PostgreSQL: force TLS"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# GOES WRONG
#  - Pod times out connecting  -> security group/route problem (check the rds SG rule and that the pod runs on a node with node-sg).
#  - "password authentication failed" -> the secret and the DB diverged (someone changed one side); re-sync from the secret.
#  - "no pg_hba.conf entry ... no encryption" -> client not using TLS (force_ssl).
resource "aws_db_instance" "this" {
  identifier = "${local.name}-orders"

  engine                = "postgres"
  engine_version        = var.engine_version
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.allocated_storage_gb * 5
  storage_type          = "gp3"

  db_name  = var.db_name
  username = local.out.secrets.db_username
  password = local.out.secrets.rds_password
  port     = 5432

  storage_encrypted = true
  kms_key_id        = local.out.kms.data_key_arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [local.out.sg.rds_security_group_id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period    = var.backup_retention_days
  backup_window              = "03:00-04:00"
  maintenance_window         = "sun:04:30-sun:05:30"
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name}-orders-final"

  apply_immediately = true # lab convenience; PRODUCTION: false (apply in the maintenance window)

  tags = { Name = "${local.name}-orders" }

  lifecycle {
    ignore_changes = [engine_version]
  }
}

# Config publication (see 18-parameter-store): the order-service and worker read these at startup.
resource "aws_ssm_parameter" "config" {
  for_each = {
    "rds/host"   = aws_db_instance.this.address
    "rds/port"   = tostring(aws_db_instance.this.port)
    "rds/dbname" = aws_db_instance.this.db_name
  }

  name  = "${local.ssm_prefix}/${each.key}"
  type  = "String"
  value = each.value
}
