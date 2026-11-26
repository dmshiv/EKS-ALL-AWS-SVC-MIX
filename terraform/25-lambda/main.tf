# =============================================================================
# 25-lambda : serverless reaction to order events (EventBridge -> Lambda -> SNS)
# =============================================================================
#
#   EventBridge rule (24) --async invoke--> Lambda order-notifier --sns:Publish--> SNS topic (23) --> subscribers (SQS, e-mail)
#                                              ^ failures -> retries (3) -> EventBridge target DLQ (24)
#
# WHY A LAMBDA HERE (instead of another pod): a tiny stateless reaction to an event; zero idle cost; scales to zero and out.
# INVOCATION MODEL: EventBridge invokes Lambda ASYNCHRONOUSLY (fire and forget). Lambda queues the event, retries on error, and
#   only then does EventBridge send it to the DLQ. Handlers must therefore be idempotent (the same event may be delivered twice).
# NETWORK: the function is NOT in the VPC: it only talks to the public SNS API, so it needs no ENIs, NAT or endpoints. (A VPC-attached
#   Lambda would need NAT/endpoints to reach SNS and would add cold-start latency.)
# IAM (least privilege): write its own logs, publish to ONE topic, use ONE key. Plus a resource policy letting EventBridge invoke it.
# COST: 1M requests + 400,000 GB-s free per month; arm64 (Graviton) is ~20% cheaper per ms.
# DEPENDS ON: 16-kms, 23-sns, 24-eventbridge.

# Code is zipped from application/lambda/order-notifier at plan time (source_code_hash redeploys on any change).
data "archive_file" "notifier" {
  type        = "zip"
  source_dir  = "${path.module}/../../application/lambda/order-notifier"
  output_path = "${path.module}/.build/order-notifier.zip"
  excludes    = ["__pycache__", "*.pyc", "tests"]
}

# WHY:        Created explicitly so retention is bounded; otherwise Lambda creates an unbounded group on first invoke.
# DEPENDS:    Used by the notifier function.
# GOES WRONG: Unbounded logs are a slow cost leak.
resource "aws_cloudwatch_log_group" "notifier" {
  name              = "/aws/lambda/${local.name}-order-notifier"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# WHY:        Execution role: what the function itself may do (not who may invoke it).
# DEPENDS:    Trusted by lambda.amazonaws.com.
# GOES WRONG: Missing trust = function create fails; over-broad permissions here are a common finding in Security Hub.
resource "aws_iam_role" "notifier" {
  name               = "${local.name}-order-notifier"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "notifier" {
  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.notifier.arn}:*"]
  }

  statement {
    sid       = "PublishNotifications"
    actions   = ["sns:Publish"]
    resources = [local.sns_topic_arn]
  }

  # The topic is encrypted with the CMK, so the publisher also needs the key (the other classic AccessDenied).
  statement {
    sid       = "UseDataKeyForEncryptedTopic"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [local.data_key_arn]
  }
}

# WHY:        Least privilege: publish to the one SNS topic and use the CMK.
# DEPENDS:    Depends on the notifier role and 23-sns.
# GOES WRONG: SNS publish AccessDenied appears in the function's CloudWatch logs, not in the caller.
resource "aws_iam_role_policy" "notifier" {
  name   = "notifier"
  role   = aws_iam_role.notifier.id
  policy = data.aws_iam_policy_document.notifier.json
}

# WHY:        Event-driven glue: reacts to EventBridge events and publishes notifications without any always-on pod.
# DEPENDS:    Depends on the role, log group and packaged code; invoked by the EventBridge rule (24).
# GOES WRONG: Timeout/memory too low, or missing dead-letter handling, loses events; check the function logs and EventBridge target errors.
resource "aws_lambda_function" "notifier" {
  function_name = "${local.name}-order-notifier"
  role          = aws_iam_role.notifier.arn
  runtime       = var.lambda_runtime
  handler       = "handler.handler"
  architectures = ["arm64"]
  timeout       = var.lambda_timeout_seconds
  memory_size   = 128

  filename         = data.archive_file.notifier.output_path
  source_code_hash = data.archive_file.notifier.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = local.sns_topic_arn
      LOG_LEVEL     = "INFO"
    }
  }

  depends_on = [aws_cloudwatch_log_group.notifier, aws_iam_role_policy.notifier]

  tags = { Name = "${local.name}-order-notifier" }
}

# RESOURCE-BASED POLICY on the Lambda: lets the EventBridge SERVICE invoke it, only for THIS rule.
# Forgetting this = the rule matches but nothing runs (check the rule's FailedInvocations metric).
resource "aws_lambda_permission" "events" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notifier.function_name
  principal     = "events.amazonaws.com"
  source_arn    = local.out.events.rule_arn
}

# THE TARGET: wires the rule (24) to the function. Retries then DLQ (also defined in 24).
resource "aws_cloudwatch_event_target" "notifier" {
  rule           = local.out.events.rule_name
  event_bus_name = local.out.events.event_bus_name
  target_id      = "order-notifier"
  arn            = aws_lambda_function.notifier.arn

  retry_policy {
    maximum_retry_attempts       = 3
    maximum_event_age_in_seconds = 3600
  }

  dead_letter_config {
    arn = local.out.events.events_dlq_arn
  }

  depends_on = [aws_lambda_permission.events]
}
