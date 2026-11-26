# =============================================================================
# 23-sns : order notifications (pub/sub fan-out)
# =============================================================================
#
#   notifier Lambda (15) --Publish--> [ SNS topic: order-notifications ] --+--> SQS "notifications" queue  (a consumer app can poll it)
#                                                                           +--> e-mail (optional)
#                                                                           +--> (future) Lambda / HTTPS / mobile push
#
# WHY SNS: one event, many independent consumers. Adding a new consumer = adding a subscription; the publisher does not change.
# WHY SNS -> SQS (not SNS -> app directly): SNS is push-and-forget with limited retries. Putting an SQS queue behind each
#   subscriber gives every consumer its own durable buffer, retries and DLQ. This "topic + queue per consumer" fan-out is
#   the standard AWS pattern.
# COST: $0.50 per million publishes; SQS deliveries free; e-mail 1,000/month free.

# WHY:        Fan-out: one published order event reaches many independent consumers.
# DEPENDS:    Published by the notifier Lambda; consumed by subscriptions.
# GOES WRONG: No subscribers = messages are silently dropped.
resource "aws_sns_topic" "orders" {
  name              = "${local.name}-order-notifications"
  kms_master_key_id = data.terraform_remote_state.kms.outputs.data_key_arn

  tags = { Name = "${local.name}-order-notifications" }
}

# The subscriber queue. In a real system this would belong to the consuming team.
resource "aws_sqs_queue" "notifications" {
  name                              = "${local.name}-notifications"
  message_retention_seconds         = 345600
  receive_wait_time_seconds         = 20
  kms_master_key_id                 = data.terraform_remote_state.kms.outputs.data_key_arn
  kms_data_key_reuse_period_seconds = 300

  tags = { Name = "${local.name}-notifications" }
}

# RESOURCE POLICY: without it SNS gets AccessDenied delivering to the queue and the subscription looks "confirmed" but
# stays silent (classic gotcha). aws:SourceArn pins it to THIS topic only.
data "aws_iam_policy_document" "notifications_queue" {
  statement {
    sid       = "AllowSnsToSend"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.notifications.arn]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.orders.arn]
    }
  }
}

# WHY:        An SNS topic can only deliver to an SQS queue if the queue policy allows that topic ARN.
# DEPENDS:    Depends on the notifications queue and the topic.
# GOES WRONG: Subscription shows confirmed but queue stays empty = this policy missing (SNS delivery failures in CloudWatch).
resource "aws_sqs_queue_policy" "notifications" {
  queue_url = aws_sqs_queue.notifications.id
  policy    = data.aws_iam_policy_document.notifications_queue.json
}

# raw_message_delivery=true: the queue receives the original message body instead of the SNS JSON envelope.
resource "aws_sns_topic_subscription" "queue" {
  topic_arn            = aws_sns_topic.orders.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.notifications.arn
  raw_message_delivery = true

  depends_on = [aws_sqs_queue_policy.notifications]
}

# WHY:        Optional human subscriber; email subscriptions need manual confirmation.
# DEPENDS:    Depends on the topic and var.alert_email.
# GOES WRONG: Unconfirmed = no mails; the confirmation mail often lands in spam.
resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.orders.arn
  protocol  = "email"
  endpoint  = var.notification_email
}
