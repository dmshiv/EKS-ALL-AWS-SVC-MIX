# 29-alb: what Terraform owns around the ALB

## Objective
Create the access-log bucket the Ingress references; explain who owns the ALB itself (the controller).

## Architecture
```
Internet -> CloudFront -> WAF -> ALB -> target group -> pod ; ALB access logs -> S3 (SSE-S3)
```

## AWS services and cost
ALB itself ~$16/month (created by Ingress). Log bucket cents.

## Prerequisites
Folders applied before this one: none. Apply order for the whole project: `scripts/execution-order.txt`. 

## Inputs from previous folders
None. This folder reads no other folder's state (it needs only the S3 backend from `00-bootstrap`).

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `access_logs_bucket` | `99-capstone` |
| `access_logs_prefix` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/29-alb/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- S3 log bucket (SSE-S3: ALB logs do not support KMS), lifecycle, TLS-only policy allowing the ELB log-delivery principal.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 29-alb plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 29-alb apply     # re-plans, asks you to type '29-alb', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws s3 ls s3://<bucket>/alb/` | Log files appear after traffic (several minutes). |
| `aws elbv2 describe-load-balancers` | The ALB created by the Ingress. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **503 from ALB**: No healthy targets: wrong health-check path, readiness failing, or SG blocks ALB to pod.
- **502**: Pod closed connection early.
- **504**: Slow pod / idle timeout.

## Cleanup
Log bucket force_destroy deletes logs. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 29-alb destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 29-alb'
```

## Lab vs production
Access logs plus WAF logs to a central bucket; alarms on 5xx and unhealthy hosts.

## Interview
**30 seconds:** The ALB lifecycle follows the Ingress, so Terraform owns only supporting resources (logs, WAF ACL, certificate).

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- Why not create the ALB in Terraform?
- Troubleshoot a 5xx from the ALB.

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
