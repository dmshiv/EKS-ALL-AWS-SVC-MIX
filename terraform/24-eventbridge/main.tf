# =============================================================================
# 24-eventbridge : business events bus, routing rule, archive and delivery DLQ
# =============================================================================
#
#   worker Pod --events:PutEvents--> [ custom event bus: cloudcart-lab ]
#                                         | rule: source=cloudcart.orders, detail-type=OrderProcessed
#                                         v
#                                    target = Lambda order-notifier (created in 25-lambda)  --> SNS (23) --> subscribers
#                                         ^ undeliverable events after retries -> SQS DLQ (below)
#
# WHEN EVENTBRIDGE vs THE OTHERS (interview):
#   - SQS: "do this work" (a command): one consumer group pulls at its own pace.
#   - SNS: "tell everyone" with simple topic fan-out and attribute filters.
#   - EventBridge: "something happened" (a fact): route by CONTENT with rich patterns to many AWS targets, with schema registry,
#     archive/replay and SaaS sources. Producers do not know who listens.
#   - Lambda: short stateless glue code with no pods to run; 15-minute limit; scales to zero.
#
# COST: custom-bus events $1.00 per million; archive billed per GB stored; rules/targets free.
# DEPENDS ON: 16-kms, 08-pod-identity.   DEPENDED ON BY: 25-lambda (target + permission).

# WHY:        A custom bus keeps application events separate from AWS service events on the default bus.
# DEPENDS:    Producers: worker/order-service; consumers: rules in this folder.
# GOES WRONG: Events put on the default bus never match rules on this bus.
resource "aws_cloudwatch_event_bus" "this" {
  name = local.name

  tags = { Name = local.name }
}

# Keep events for replay (e.g. re-run the Lambda after fixing a bug, or rebuild a downstream system). Also a DR tool.
resource "aws_cloudwatch_event_archive" "this" {
  name             = "${local.name}-archive"
  event_source_arn = aws_cloudwatch_event_bus.this.arn
  retention_days   = var.event_archive_retention_days
}

# The EVENT PATTERN is the routing contract: only OrderProcessed events from the worker reach the target.
resource "aws_cloudwatch_event_rule" "order_processed" {
  name           = "${local.name}-order-processed"
  event_bus_name = aws_cloudwatch_event_bus.this.name
  description    = "Order processed by the worker -> notify"

  event_pattern = jsonencode({
    source        = ["cloudcart.orders"]
    "detail-type" = ["OrderProcessed"]
  })
}

# EventBridge could not deliver (target throttled/failed after retries) -> park the event here instead of losing it.
resource "aws_sqs_queue" "events_dlq" {
  name                              = "${local.name}-events-dlq"
  message_retention_seconds         = 1209600
  kms_master_key_id                 = local.data_key_arn
  kms_data_key_reuse_period_seconds = 300
}

data "aws_iam_policy_document" "events_dlq" {
  statement {
    sid       = "AllowEventBridgeToSend"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.events_dlq.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.order_processed.arn]
    }
  }
}

# WHY:        EventBridge can only send failed deliveries to the DLQ if the queue policy trusts the rule.
# DEPENDS:    Depends on the DLQ and the rule.
# GOES WRONG: Without it failed deliveries are lost after retries with no trace.
resource "aws_sqs_queue_policy" "events_dlq" {
  queue_url = aws_sqs_queue.events_dlq.id
  policy    = data.aws_iam_policy_document.events_dlq.json
}

# PRODUCER PERMISSION: the worker may publish to THIS bus only. (The bus is created here, so this folder owns the grant.)
data "aws_iam_policy_document" "worker_put_events" {
  statement {
    sid       = "PublishOrderEvents"
    actions   = ["events:PutEvents"]
    resources = [aws_cloudwatch_event_bus.this.arn]
  }
}

# WHY:        The worker may only PutEvents to this bus.
# DEPENDS:    Depends on the worker role.
# GOES WRONG: AccessDenied on PutEvents = missing or wrong bus ARN.
resource "aws_iam_role_policy" "worker_put_events" {
  name   = "eventbridge-put-events"
  role   = local.worker_role
  policy = data.aws_iam_policy_document.worker_put_events.json
}

# WHY:        Publishes the bus name for the app config.
# DEPENDS:    Read by deploy scripts.
# GOES WRONG: Hard-coded names diverge between environments.
resource "aws_ssm_parameter" "bus_name" {
  name  = "${local.ssm_prefix}/events/bus_name"
  type  = "String"
  value = aws_cloudwatch_event_bus.this.name
}
