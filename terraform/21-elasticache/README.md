# 21-elasticache: catalog cache (Valkey/Redis)

## Objective
Create an encrypted cache in isolated subnets with TLS and AUTH; the app treats it as optional (fail open).

## Architecture
```
product-service -> cache hit? yes: return; no: DynamoDB then cache with TTL
```

## AWS services and cost
cache.t4g.micro ~$12/month per node, 24/7. EXPENSIVE-ish.

## Prerequisites
Folders applied before this one: `01-vpc`, `03-security-groups`, `16-kms`, `17-secrets-manager`. Apply order for the whole project: `scripts/execution-order.txt`. Needs `01-vpc`, `03-security-groups`, `16-kms`, `17-secrets-manager`.

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `01-vpc` | `database_subnet_ids` |
| `03-security-groups` | `redis_security_group_id` |
| `16-kms` | `data_key_arn` |
| `17-secrets-manager` | `redis_auth_token` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `primary_endpoint` | scripts / humans (verification, Helm values) |
| `port` | scripts / humans (verification, Helm values) |
| `replication_group_id` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/21-elasticache/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- Subnet group (database subnets), replication group with at-rest (CMK) and in-transit encryption, AUTH token from the secret.
- SSM parameters host/port.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 21-elasticache plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 21-elasticache apply     # re-plans, asks you to type '21-elasticache', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws elasticache describe-replication-groups --query 'ReplicationGroups[0].Status'` | available. |
| `kubectl logs deploy/product-service | grep redis` | `redis cache connected`. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **redis unavailable, running without cache**: Intended fail-open behaviour; find why: SG 6379 from node-sg, TLS (`rediss`), AUTH token.
- **Slow after cache restart**: Cold cache: DynamoDB load spike.

## Cleanup
Cache data is disposable; no snapshots in the lab. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 21-elasticache destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 21-elasticache'
```

## Lab vs production
PRODUCTION: 2+ nodes Multi-AZ with automatic failover, RBAC/IAM auth, snapshots if data matters, cluster mode for scale.

## Interview
**30 seconds:** A cache lowers latency and read cost; correctness must not depend on it, so the app fails open. Network and auth: private subnets, SG from nodes, TLS + token.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- Why cache?
- What if the cache is down?
- Cache-aside vs write-through?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
