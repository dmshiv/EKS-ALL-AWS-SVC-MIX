# =============================================================================
# 22-sqs : order-processing queue + dead-letter queue
# =============================================================================
#
#   order-service --SendMessage--> [ orders queue ] --ReceiveMessage (long poll)--> worker pods (N replicas)
#                                        |  after max_receive_count failed attempts
#                                        v
#                                  [ orders DLQ ]  --> CloudWatch alarm (34-cloudwatch) --> humans
#
# WHY A QUEUE: the API must answer in milliseconds, but order processing is slow/failure-prone. A queue DECOUPLES them:
#   - buffer: traffic spikes pile up in the queue instead of crashing the workers
#   - retries: a failed message becomes visible again after the visibility timeout
#   - scale: add worker pods when the queue is long (HPA/KEDA on queue depth)
# SQS vs SNS vs EventBridge (decision guide, see docs/messaging):
#   SQS         = ONE consumer group pulls work at its own pace (a work queue).
#   SNS         = PUSH one message to MANY subscribers (fan-out).
#   EventBridge = ROUTE events by content (rules/filters) from many producers to many AWS targets.
#
# SEMANTICS: Standard queue = at-least-once, best-effort ordering => workers MUST be idempotent (the same order may arrive twice).
# MESSAGE LIFECYCLE: received -> invisible for visibility_timeout -> worker deletes it (success) OR it reappears (failure/timeout)
#   -> after max_receive_count receives it goes to the DLQ.
# COST: first 1M requests/month free, then $0.40 per million. Long polling (20s) cuts empty-receive cost.

# WHY:        Messages that keep failing land here instead of blocking or looping forever; a dead-letter queue is how poison messages are isolated.
# DEPENDS:    Referenced by the orders queue redrive policy; alarmed in 34-cloudwatch.
# GOES WRONG: Nobody watching the DLQ = silent order loss: always alarm on ApproximateNumberOfMessagesVisible.
resource "aws_sqs_queue" "dlq" {
  name                              = "${local.name}-orders-dlq"
  message_retention_seconds         = 1209600 # 14 days to investigate failures
  kms_master_key_id                 = data.terraform_remote_state.kms.outputs.data_key_arn
  kms_data_key_reuse_period_seconds = 300

  tags = { Name = "${local.name}-orders-dlq" }
}

# WHY:        Decouples the Order API from the Worker: the API returns fast and the worker processes at its own pace.
# DEPENDS:    Depends on the DLQ and the CMK; produced by order-service, consumed by worker.
# GOES WRONG: visibility timeout < processing time causes duplicate processing; maxReceiveCount too low moves good messages to the DLQ.
resource "aws_sqs_queue" "orders" {
  name                              = "${local.name}-orders"
  visibility_timeout_seconds        = var.visibility_timeout_seconds
  receive_wait_time_seconds         = 20 # long polling default for consumers
  message_retention_seconds         = 345600
  kms_master_key_id                 = data.terraform_remote_state.kms.outputs.data_key_arn
  kms_data_key_reuse_period_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = { Name = "${local.name}-orders" }
}

# Only the orders queue may use this DLQ (prevents other queues dumping messages there by mistake).
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.orders.arn]
  })
}
