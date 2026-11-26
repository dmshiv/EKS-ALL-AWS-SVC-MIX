# 22-sqs: order queue and dead-letter queue

## Objective
Create the encrypted orders queue with a DLQ and give order-service send-only and worker receive-only permissions.

## Architecture
```
order-service -> SQS orders -> worker pods (long poll) ; failures x5 -> DLQ
```

## AWS services and cost
First 1M requests/month free then $0.40/M. Cheap.

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
| `orders_queue_url` | scripts / humans (verification, Helm values) |
| `orders_queue_arn` | scripts / humans (verification, Helm values) |
| `orders_queue_name` | `34-cloudwatch` |
| `dlq_arn` | scripts / humans (verification, Helm values) |
| `dlq_name` | `34-cloudwatch` |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/22-sqs/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- Orders queue: visibility 60s, long polling 20s, redrive after 5 receives; DLQ 14 days retention; redrive allow policy.
- Producer and consumer IAM policies (+ KMS via SQS only); SSM queue URL.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 22-sqs plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 22-sqs apply     # re-plans, asks you to type '22-sqs', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws sqs get-queue-attributes --queue-url <url> --attribute-names All` | RedrivePolicy present, KmsMasterKeyId set. |
| `POST /orders then kubectl logs deploy/worker` | Message consumed, order PROCESSED. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Messages processed twice**: Processing time > visibility timeout or at-least-once delivery: idempotency + longer timeout.
- **Worker AccessDenied ReceiveMessage**: Missing sqs:ReceiveMessage or kms:Decrypt.
- **Messages pile in the DLQ**: Poison message: inspect with `aws sqs receive-message` on the DLQ and fix the handler.

## Cleanup
Queued messages are lost. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 22-sqs destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 22-sqs'
```

## Lab vs production
PRODUCTION: alarm on DLQ depth and message age, FIFO if ordering matters, scale workers on queue depth (KEDA).

## Interview
**30 seconds:** SQS decouples the API from slow processing: buffering, retries via visibility timeout, DLQ for poison messages, scale workers on depth. Delivery is at-least-once so handlers are idempotent.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- SQS vs SNS vs EventBridge?
- What is the visibility timeout?
- How do you handle poison messages?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
