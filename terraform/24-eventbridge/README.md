# 24-eventbridge: business events bus

## Objective
Create the custom event bus, archive, routing rule and delivery DLQ; allow the worker to publish.

## Architecture
```
worker -> PutEvents -> bus -> rule (source=cloudcart.orders, detail-type=OrderProcessed) -> target (25-lambda); undeliverable -> DLQ
```

## AWS services and cost
$1/M custom events; archive per GB. Cheap.

## Prerequisites
Folders applied before this one: `08-pod-identity`, `16-kms`. Apply order for the whole project: `scripts/execution-order.txt`. Needs `16-kms`, `08-pod-identity`.

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `08-pod-identity` | `role_names` |
| `16-kms` | `data_key_arn` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `event_bus_name` | `25-lambda` |
| `event_bus_arn` | scripts / humans (verification, Helm values) |
| `rule_name` | `25-lambda` |
| `rule_arn` | `25-lambda` |
| `events_dlq_arn` | `25-lambda` |
| `events_dlq_name` | `34-cloudwatch` |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/24-eventbridge/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- Bus, archive (replay), rule with an event pattern, DLQ with a queue policy scoped to the rule.
- Worker PutEvents policy limited to this bus.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 24-eventbridge plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 24-eventbridge apply     # re-plans, asks you to type '24-eventbridge', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws events list-rules --event-bus-name cloudcart-lab` | Rule ENABLED. |
| `aws events put-events --entries ...` | Test event reaches the Lambda (25). |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Rule matches but nothing runs**: Target/permission lives in 25-lambda; check FailedInvocations metric.
- **Events not matching**: Pattern mismatch (source/detail-type): test with `aws events test-event-pattern`.

## Cleanup
Safe to destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 24-eventbridge destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 24-eventbridge'
```

## Lab vs production
PRODUCTION: schema registry, multiple rules, archive/replay runbooks, cross-account buses.

## Interview
**30 seconds:** EventBridge routes facts by content to many targets; producers do not know consumers. Use SQS for commands, SNS for simple fan-out, EventBridge for content routing.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- EventBridge vs SNS?
- How does replay help recovery?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
