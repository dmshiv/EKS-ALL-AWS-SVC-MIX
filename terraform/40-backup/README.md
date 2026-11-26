# 40-backup: AWS Backup and DR copy

## Objective
Define a vault, daily plan and selection for RDS, DynamoDB and EFS, with an optional cross-region copy.

## Architecture
```
Backup plan (cron) -> vault (KMS) ; selection by ARN -> recovery points ; optional copy to a DR region vault
```

## AWS services and cost
Backup storage per GB-month (+ cross-region transfer).

## Prerequisites
Folders applied before this one: `14-efs`, `16-kms`, `19-rds`, `20-dynamodb`. Apply order for the whole project: `scripts/execution-order.txt`. Needs `14-efs`, `19-rds`, `20-dynamodb`, `16-kms`.

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `14-efs` | `efs_file_system_id` |
| `16-kms` | `data_key_arn` |
| `19-rds` | `db_identifier` |
| `20-dynamodb` | `table_arn` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `vault_name` | scripts / humans (verification, Helm values) |
| `backup_plan_id` | scripts / humans (verification, Helm values) |
| `backup_role_arn` | scripts / humans (verification, Helm values) |
| `dr_vault_name` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/40-backup/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- Vault + DR vault, backup role, plan with lifecycle, selection of the three data stores.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 40-backup plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 40-backup apply     # re-plans, asks you to type '40-backup', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws backup list-backup-plans` | Plan listed. |
| `aws backup list-recovery-points-by-backup-vault --backup-vault-name cloudcart-lab-vault` | Recovery points after the first run. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Job fails AccessDenied**: Backup role lacks service policies or KMS grant.

## Cleanup
Recovery points may need manual deletion; vault lock prevents deletion. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 40-backup destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 40-backup'
```

## Lab vs production
RPO/RTO driven schedules, vault lock, cross-account copies, restore testing.

## Interview
**30 seconds:** Backups protect against deletion and corruption; DR needs restore drills, cross-region copies, and defined RPO/RTO.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- RTO vs RPO?
- What would you do if the cluster is lost?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
