# 20-dynamodb: product catalog

## Objective
Create an on-demand, encrypted, point-in-time-recoverable table with a category index and seed data; grant product-service access.

## Architecture
```
product-service -> DynamoDB gateway endpoint (free) -> table products (+ GSI category-index)
```

## AWS services and cost
On-demand $1.25/M writes, $0.25/M reads; PITR adds storage cost. Cheap.

## Prerequisites
Folders applied before this one: `08-pod-identity`, `16-kms`. Apply order for the whole project: `scripts/execution-order.txt`. Needs `16-kms`, `08-pod-identity`.

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `08-pod-identity` | `role_names` |
| `16-kms` | `data_key_arn` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `table_name` | `34-cloudwatch` |
| `table_arn` | `40-backup` |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/20-dynamodb/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- `aws_dynamodb_table.products`: hash key product_id, GSI by category, SSE with CMK, PITR.
- Seed items; IAM policy (table + `/index/*`); SSM parameter.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 20-dynamodb plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 20-dynamodb apply     # re-plans, asks you to type '20-dynamodb', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws dynamodb scan --table-name cloudcart-lab-products --max-items 3` | Seed products. |
| `curl http://product-service:8080/products (port-forward)` | `source: dynamodb` then `cache` on the second call. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **AccessDeniedException on Query of the index**: Policy missing `.../index/*`.
- **ThrottlingException**: On-demand has initial limits; hot partition: redesign keys.

## Cleanup
DESTRUCTIVE: table and data deleted; PITR lets you restore only while the table exists. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 20-dynamodb destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 20-dynamodb'
```

## Lab vs production
PRODUCTION: deletion protection, global tables for DR, DAX if needed, on-demand vs provisioned decision from traffic data.

## Interview
**30 seconds:** DynamoDB is key-value storage modeled around access patterns; IAM-only auth; encrypted at rest; reached privately through a gateway endpoint.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- How do you choose a partition key?
- Scan vs Query?
- On-demand vs provisioned?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
