# 23-sns: order notifications (fan-out)

## Objective
Create an encrypted topic with an SQS subscriber (and optional e-mail) to demonstrate pub/sub fan-out.

## Architecture
```
Lambda (25) -> SNS topic -> SQS notifications queue | e-mail | future subscribers
```

## AWS services and cost
$0.50/M publishes; SQS deliveries free.

## Prerequisites
Folders applied before this one: `16-kms`. Apply order for the whole project: `scripts/execution-order.txt`. Needs `16-kms`.

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `16-kms` | `data_key_arn` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `topic_arn` | `25-lambda` |
| `notifications_queue_url` | scripts / humans (verification, Helm values) |
| `notifications_queue_arn` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/23-sns/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- Encrypted topic; subscriber queue with a policy allowing the topic (`aws:SourceArn`); raw message delivery.
- SSM parameter topic ARN.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 23-sns plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 23-sns apply     # re-plans, asks you to type '23-sns', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws sns list-subscriptions-by-topic --topic-arn <arn>` | Confirmed SQS subscription. |
| `aws sqs receive-message --queue-url <notifications>` | Appears after an order is processed. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Subscription confirmed but no messages**: Queue policy missing or KMS key policy lacks sns.amazonaws.com.
- **E-mail not received**: Click the confirmation e-mail.

## Cleanup
Safe to destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 23-sns destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 23-sns'
```

## Lab vs production
PRODUCTION: filter policies, DLQ per subscription, one queue per consumer.

## Interview
**30 seconds:** SNS pushes one message to many subscribers; putting an SQS queue behind each consumer gives each durable buffering and retries.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- SNS vs SQS?
- Why SNS -> SQS fan-out?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
