# 39-config: configuration history and compliance

## Objective
Record resource configuration changes (disabled by default; billed per item).

## Architecture
```
resource changes -> Config recorder -> S3 history + rules
```

## AWS services and cost
$0.003 per configuration item: can surprise you.

## Prerequisites
Folders applied before this one: none. Apply order for the whole project: `scripts/execution-order.txt`. 

## Inputs from previous folders
None. This folder reads no other folder's state (it needs only the S3 backend from `00-bootstrap`).

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `config_bucket` | scripts / humans (verification, Helm values) |
| `recorder_name` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/39-config/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- Bucket + policy, service role, recorder, delivery channel, recorder status (ordered with depends_on).

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 39-config plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 39-config apply     # re-plans, asks you to type '39-config', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws configservice describe-configuration-recorder-status` | recording true. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Apply fails: recorder exists**: One per region.

## Cleanup
History in the bucket is deleted with force_destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 39-config destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 39-config'
```

## Lab vs production
Conformance packs, aggregators, remediation via SSM Automation.

## Interview
**30 seconds:** Config answers 'what did this look like last Tuesday?' and evaluates rules.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- Config vs CloudTrail?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
