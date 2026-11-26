# 34-cloudwatch: alerts, alarms and dashboard

## Objective
Create the alerts SNS topic, alarms on the platform's key failure signals and one dashboard.

## Architecture
```
CloudWatch alarms (queue age, DLQ, Lambda errors, RDS CPU/connections, ...) -> SNS alerts topic -> e-mail
```

## AWS services and cost
$0.10/alarm/month; dashboard $3/month; custom metrics extra.

## Prerequisites
Folders applied before this one: `06-eks`, `16-kms`, `19-rds`, `20-dynamodb`, `21-elasticache`, `22-sqs`, `24-eventbridge`, `25-lambda`. Apply order for the whole project: `scripts/execution-order.txt`. Needs states of 06-eks, 10, 19, 21, 22, 24, 25 (names for dimensions).

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `06-eks` | `cluster_name` |
| `16-kms` | `data_key_arn` |
| `19-rds` | `db_identifier` |
| `20-dynamodb` | `table_name` |
| `21-elasticache` | (state must exist) |
| `22-sqs` | `orders_queue_name`, `dlq_name` |
| `24-eventbridge` | `events_dlq_name` |
| `25-lambda` | `lambda_function_name` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `alerts_topic_arn` | scripts / humans (verification, Helm values) |
| `dashboard_name` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/34-cloudwatch/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- Encrypted alerts topic (+ optional e-mail).
- Alarms per dependency; dashboard combining SQS, Lambda, RDS, DynamoDB and ContainerInsights widgets.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 34-cloudwatch plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 34-cloudwatch apply     # re-plans, asks you to type '34-cloudwatch', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws cloudwatch describe-alarms --query 'MetricAlarms[].[AlarmName,StateValue]'` | Alarms exist (INSUFFICIENT_DATA until traffic). |
| `aws sqs send-message to the DLQ then wait for the alarm` | DLQ alarm fires and the e-mail arrives. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Alarm never fires**: Wrong dimension name/value or missing data treatment: `aws cloudwatch get-metric-statistics`.
- **No e-mail**: Subscription not confirmed.

## Cleanup
Safe to destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 34-cloudwatch destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 34-cloudwatch'
```

## Lab vs production
Alarms tied to SLOs, runbook links, composite alarms, on-call routing, anomaly detection.

## Interview
**30 seconds:** Logs explain what happened, metrics show how it behaves over time, alarms tell humans. Alarms must be actionable.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- Logs vs metrics vs traces?
- Which alarms would you page on?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
