# 36-cloudtrail: who called which AWS API

## Objective
Record management events in a multi-region trail with log file validation.

## Architecture
```
AWS API calls (console, CLI, Terraform, pods via Pod Identity) -> CloudTrail -> S3 (SSE-S3, validated)
```

## AWS services and cost
First management trail per account free; storage cents.

## Prerequisites
Folders applied before this one: none. Apply order for the whole project: `scripts/execution-order.txt`. 

## Inputs from previous folders
None. This folder reads no other folder's state (it needs only the S3 backend from `00-bootstrap`).

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `trail_name` | scripts / humans (verification, Helm values) |
| `trail_bucket` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/36-cloudtrail/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- Hardened S3 bucket + policy scoped to this trail (`aws:SourceArn`); `aws_cloudtrail` multi-region with validation.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 36-cloudtrail plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 36-cloudtrail apply     # re-plans, asks you to type '36-cloudtrail', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws cloudtrail get-trail-status --name cloudcart-lab-trail` | IsLogging true. |
| `aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRole` | Recent role sessions, including pods. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Trail not delivering**: Bucket policy missing the SourceArn statement.

## Cleanup
force_destroy deletes audit logs (lab only). Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 36-cloudtrail destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 36-cloudtrail'
```

## Lab vs production
Organization trail to a log-archive account, CloudTrail Lake, data events for sensitive buckets.

## Interview
**30 seconds:** CloudTrail answers who called which AWS API. Kubernetes API calls are in the EKS audit log, not CloudTrail.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- CloudTrail vs EKS audit log?
- How would you investigate an AccessDenied?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
