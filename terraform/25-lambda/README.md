# 25-lambda: serverless reaction to order events

## Objective
Deploy the order-notifier Lambda, its least-privilege role, the EventBridge permission and the rule target.

## Architecture
```
EventBridge rule -> async invoke -> Lambda -> SNS publish ; failures -> retries -> DLQ
```

## AWS services and cost
1M requests + 400k GB-s free/month.

## Prerequisites
Folders applied before this one: `16-kms`, `23-sns`, `24-eventbridge`. Apply order for the whole project: `scripts/execution-order.txt`. Needs `16-kms`, `23-sns`, `24-eventbridge`; source in `application/lambda/order-notifier`.

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `16-kms` | `data_key_arn` |
| `23-sns` | `topic_arn` |
| `24-eventbridge` | `event_bus_name`, `rule_name`, `rule_arn`, `events_dlq_arn` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `lambda_function_name` | `34-cloudwatch` |
| `lambda_function_arn` | scripts / humans (verification, Helm values) |
| `lambda_log_group` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/25-lambda/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- `archive_file` zip, `aws_lambda_function` (arm64, not in a VPC).
- Role: own logs, sns:Publish on one topic, KMS for the encrypted topic.
- `aws_lambda_permission` for events.amazonaws.com scoped to the rule; `aws_cloudwatch_event_target` with retries and DLQ.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 25-lambda plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 25-lambda apply     # re-plans, asks you to type '25-lambda', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws lambda invoke --function-name cloudcart-lab-order-notifier --payload '{...}' out.json` | Returns published true. |
| `aws logs tail /aws/lambda/cloudcart-lab-order-notifier` | Invocation logs. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **AccessDenied sns:Publish / KMS**: Role missing publish or key permissions (encrypted topic).
- **Never invoked**: Missing lambda permission or wrong event pattern.

## Cleanup
Safe to destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 25-lambda destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 25-lambda'
```

## Lab vs production
PRODUCTION: reserved concurrency, DLQ/destinations, X-Ray, signed code, VPC only if needed.

## Interview
**30 seconds:** Lambda is event-driven glue: EventBridge invokes it asynchronously with retries and a DLQ; it needs its own role and a resource policy for the caller.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- Sync vs async invocation?
- How do you handle Lambda failures?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
