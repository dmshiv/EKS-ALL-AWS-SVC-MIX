# Data stores

| Store | Used for | Network | Auth | Failure behaviour |
|---|---|---|---|---|
| RDS PostgreSQL | orders (relational, transactional) | isolated subnet, SG from node-sg | password from Secrets Manager, TLS | single-AZ restore from backup; Multi-AZ fails over in ~1-2 min |
| DynamoDB | product catalog (key-value, access patterns) | gateway endpoint | IAM only | managed, regional; throttling on hot keys |
| ElastiCache | read cache | isolated subnet, SG | AUTH token + TLS | app fails open to DynamoDB |

RDS vs Aurora: see decisions/adr-rds-vs-aurora.md. Connection pooling: small pool per pod; RDS Proxy in production.
DynamoDB modelling: partition key product_id; GSI category-index for category queries; avoid Scan.
Backups: RDS automated backups + PITR, DynamoDB PITR, AWS Backup plan (folder 40).
