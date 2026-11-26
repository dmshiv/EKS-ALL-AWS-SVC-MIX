# 37-guardduty: threat detection

## Objective
Enable GuardDuty with EKS audit-log monitoring (and optional runtime monitoring).

## Architecture
```
CloudTrail + VPC/DNS logs + EKS audit log -> GuardDuty -> findings
```

## AWS services and cost
Usage-based; 30-day free trial; runtime monitoring per vCPU-hour.

## Prerequisites
Folders applied before this one: none. Apply order for the whole project: `scripts/execution-order.txt`. 

## Inputs from previous folders
None. This folder reads no other folder's state (it needs only the S3 backend from `00-bootstrap`).

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `detector_id` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/37-guardduty/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- `aws_guardduty_detector` + EKS_AUDIT_LOGS feature; optional RUNTIME_MONITORING.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 37-guardduty plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 37-guardduty apply     # re-plans, asks you to type '37-guardduty', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws guardduty list-detectors` | One detector. |
| `aws guardduty create-sample-findings --detector-id <id>` | Sample findings appear. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Apply fails: detector exists**: One per region: import it or disable via variable.

## Cleanup
Safe to destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 37-guardduty destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 37-guardduty'
```

## Lab vs production
Send findings to Security Hub/EventBridge with auto-remediation and triage ownership.

## Interview
**30 seconds:** GuardDuty is detective, not preventive; it needs people to triage findings.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- What does it see for EKS?
- Detective vs preventive controls?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
