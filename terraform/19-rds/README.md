# 19-rds: PostgreSQL for orders

## Objective
Create an encrypted PostgreSQL instance in isolated subnets, reachable only from nodes, with credentials from Secrets Manager.

## Architecture
```
order-service -> node ENI -> [rds SG: 5432 from node-sg] -> RDS (database subnet, TLS enforced)
```

## AWS services and cost
db.t4g.micro ~$12/month + gp3. Multi-AZ doubles it. EXPENSIVE-ish, 24/7 until deleted.

## Prerequisites
Folders applied before this one: `01-vpc`, `03-security-groups`, `16-kms`, `17-secrets-manager`. Apply order for the whole project: `scripts/execution-order.txt`. Needs `01-vpc`, `03-security-groups`, `16-kms`, `17-secrets-manager`.

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `01-vpc` | `database_subnet_ids` |
| `03-security-groups` | `rds_security_group_id` |
| `16-kms` | `data_key_arn` |
| `17-secrets-manager` | `db_username`, `rds_password` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `db_address` | scripts / humans (verification, Helm values) |
| `db_port` | scripts / humans (verification, Helm values) |
| `db_name` | scripts / humans (verification, Helm values) |
| `db_identifier` | `34-cloudwatch`, `40-backup` |
| `db_arn` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/19-rds/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- Subnet group on database subnets; parameter group `rds.force_ssl=1`.
- `aws_db_instance.this`: encrypted (CMK), private, backups, password from the secret, optional Multi-AZ.
- SSM parameters host/port/dbname.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 19-rds plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 19-rds apply     # re-plans, asks you to type '19-rds', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws rds describe-db-instances --db-instance-identifier cloudcart-lab-orders --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address,StorageEncrypted,PubliclyAccessible]'` | available, host, true, false. |
| `kubectl -n cloudcart get pods -l app.kubernetes.io/name=order-service` | Ready: its /ready probe opens a DB connection. |
| `curl -X POST .../orders (port-forward)` | 202 with an order id; row exists. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Pod connection timeout**: SG source/route problem (two conditions: routing in the VPC + rds SG allows node-sg). `nc -vz <host> 5432` from a pod.
- **password authentication failed**: Secret and DB diverged.
- **no pg_hba.conf entry ... no encryption**: Client not using TLS (sslmode=require).
- **too many clients**: Pool size x replicas exceeds max_connections: lower pool, add RDS Proxy.

## Cleanup
DESTRUCTIVE: `skip_final_snapshot=true` (lab) deletes the data. Production: final snapshot + deletion protection. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 19-rds destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 19-rds'
```

## Lab vs production
LAB: single-AZ micro. PRODUCTION: Multi-AZ, RDS Proxy, rotation, Performance Insights, deletion protection, read replicas; consider Aurora (docs/decisions/adr-rds-vs-aurora.md).

## Interview
**30 seconds:** RDS PostgreSQL in isolated subnets; pods reach it through routing plus an SG that allows the node SG; credentials come from Secrets Manager at runtime.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- How does a pod connect to RDS?
- RDS vs Aurora?
- How do you secure RDS?
- What does Multi-AZ protect against?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
