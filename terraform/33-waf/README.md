# 33-waf: AWS WAF (regional, for the ALB)

## Objective
Create a regional web ACL with a rate limit and AWS managed rule groups, with logging; the Ingress attaches it to the ALB.

## Architecture
```
CloudFront -> [WAF web ACL] -> ALB -> pod ; rules: rate limit, Common, KnownBadInputs, SQLi, IP reputation
```

## AWS services and cost
$5/month per ACL + $1/month per rule + $0.60/M requests. EXPENSIVE-ish: destroy after the lab.

## Prerequisites
Folders applied before this one: none. Apply order for the whole project: `scripts/execution-order.txt`. 

## Inputs from previous folders
None. This folder reads no other folder's state (it needs only the S3 backend from `00-bootstrap`).

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `web_acl_arn` | `99-capstone` |
| `web_acl_name` | scripts / humans (verification, Helm values) |
| `waf_log_group` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/33-waf/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- `aws_wafv2_web_acl.alb` (REGIONAL), default allow, rate-based rule, managed groups with `managed_rules_action` (none = enforce, count = observe).
- Logging to a CloudWatch log group named `aws-waf-logs-...`.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Kubernetes
Attached by the Ingress annotation `alb.ingress.kubernetes.io/wafv2-acl-arn` (kubernetes/ingress, helm/cloudcart).

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 33-waf plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 33-waf apply     # re-plans, asks you to type '33-waf', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws wafv2 list-web-acls --scope REGIONAL` | ACL listed. |
| `curl 'http://<alb>/?id=1%27%20OR%201=1--'` | 403 from the SQLi rule (when enforcing). |
| `aws logs tail aws-waf-logs-cloudcart-lab` | Shows the terminating rule. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Legitimate users get 403**: Managed rule false positive: switch to count, read sampled requests, add an exception.
- **ACL not applied**: Annotation missing or ARN wrong; check the ALB's `WebACL` association.

## Cleanup
Safe to destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 33-waf destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 33-waf'
```

## Lab vs production
Observe-first rollout, bot control, per-path rate limits, WAF + Shield Advanced for critical apps.

## Interview
**30 seconds:** WAF filters layer-7 attacks before traffic reaches pods. It does not replace input validation, IAM or network controls.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- Count vs block?
- Regional vs CloudFront scope?
- What can WAF not protect against?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
