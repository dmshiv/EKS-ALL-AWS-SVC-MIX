# 38-security-hub: central findings and best-practice checks

## Objective
Enable Security Hub with the AWS Foundational Security Best Practices standard (disabled by default).

## Architecture
```
GuardDuty, Config, Inspector -> Security Hub -> score/findings
```

## AWS services and cost
Per security check and per ingested finding; 30-day trial.

## Prerequisites
Folders applied before this one: none. Apply order for the whole project: `scripts/execution-order.txt`. 

## Inputs from previous folders
None. This folder reads no other folder's state (it needs only the S3 backend from `00-bootstrap`).

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `securityhub_enabled` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/38-security-hub/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- `aws_securityhub_account` and the FSBP standards subscription (count-gated).

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 38-security-hub plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 38-security-hub apply     # re-plans, asks you to type '38-security-hub', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws securityhub get-findings --max-items 5` | Expect findings (public endpoint, single NAT...): reading them is the exercise. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Controls show no data**: Enable AWS Config (39).

## Cleanup
Safe to destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 38-security-hub destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 38-security-hub'
```

## Lab vs production
Aggregation across accounts, suppression rules, ticket integration.

## Interview
**30 seconds:** Security Hub aggregates findings and scores compliance; it does not fix anything.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- Which findings would you expect here and why?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
