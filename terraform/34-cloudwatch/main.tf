# =============================================================================
# 34-cloudwatch : alerts topic + alarms + dashboard (logs/metrics collection is 35-container-insights)
# =============================================================================
#
#   SIGNALS                     WHAT IT ANSWERS                         WHERE IT LIVES HERE
#   logs     (events, text)     "what happened in this request/pod?"    CloudWatch Logs (Fluent Bit from the add-on, Lambda, WAF, EKS control plane)
#   metrics  (numbers/time)     "is it slow/failing/saturated? trend?"   CloudWatch Metrics (AWS service metrics + Container Insights)
#   traces   (request path)     "WHICH hop made it slow?"                X-Ray / OpenTelemetry (docs/observability: ADOT add-on exercise)
#   audit    (who did what)     "who changed/deleted X?"                 EKS audit logs (06), CloudTrail (26)
#
#   Pods --stdout--> node /var/log/containers --Fluent Bit (add-on DaemonSet)--> /aws/containerinsights/<cluster>/application
#   kubelet/cAdvisor --> CloudWatch agent (add-on) --> ContainerInsights namespace metrics (pod/node CPU, memory, restarts)
#   AWS services --> AWS/SQS, AWS/RDS, AWS/Lambda ... metrics (free, automatic) --> alarms --> SNS alerts topic --> humans
#
# COST (watch this one): Container Insights with enhanced observability bills per observation; CloudWatch Logs ingestion is ~$0.50/GB;
#   custom metrics ~$0.30 each; alarms $0.10 each; dashboards $3 each. A chatty cluster can cost more than its nodes. Set retention on EVERY log group.
# 5xx TROUBLESHOOTING FLOW: ALB 5xx metric -> target health (are pods registered/healthy?) -> pod logs + restarts -> dependency metrics
#   (RDS connections/CPU, SQS age, DynamoDB throttles) -> recent deploy/events. See docs/troubleshooting.

# ---------------------------------------------------------------------------------------------
# ALERTS TOPIC
# ---------------------------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name              = "${local.name}-alerts"
  kms_master_key_id = local.out.kms.data_key_arn

  tags = { Name = "${local.name}-alerts" }
}

# WHY:        Delivers alarm notifications to a human.
# DEPENDS:    Depends on the alerts topic.
# GOES WRONG: Unconfirmed email subscription = alarms fire and nobody is told.
resource "aws_sns_topic_subscription" "alerts_email" {
  count = var.alert_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------------------------------------
# ALARMS (each one answers a concrete operational question)
# ---------------------------------------------------------------------------------------------
locals {
  alarm_actions = [aws_sns_topic.alerts.arn]
}

# Any message in the DLQ = an order failed max_receive_count times. This is a "someone must look" alarm, threshold 0.
resource "aws_cloudwatch_metric_alarm" "orders_dlq" {
  alarm_name          = "${local.name}-orders-dlq-not-empty"
  alarm_description   = "Orders landed in the dead-letter queue: worker is failing permanently on some messages."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = local.out.sqs.dlq_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
}

# Oldest message too old = the workers cannot keep up (scale out) or are down.
resource "aws_cloudwatch_metric_alarm" "orders_age" {
  alarm_name          = "${local.name}-orders-oldest-message-age"
  alarm_description   = "Orders are waiting longer than 5 minutes: workers down or too slow."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  dimensions          = { QueueName = local.out.sqs.orders_queue_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 300
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
}

# WHY:        Detects the notifier failing: events would otherwise be lost silently.
# DEPENDS:    Depends on the Lambda function and the alerts topic.
# GOES WRONG: treat_missing_data not-breaching hides a function that never runs.
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.name}-notifier-errors"
  alarm_description   = "The order-notifier Lambda is failing (check permissions on SNS/KMS and the events DLQ)."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = local.out.lambda.lambda_function_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
}

# WHY:        Any message in the EventBridge DLQ is a failed delivery to investigate.
# DEPENDS:    Depends on the DLQ and the alerts topic.
# GOES WRONG: Threshold of 0 with long periods is slow to alarm; keep the period short.
resource "aws_cloudwatch_metric_alarm" "events_dlq" {
  alarm_name          = "${local.name}-events-dlq-not-empty"
  alarm_description   = "EventBridge could not deliver events to the Lambda."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = local.out.events.events_dlq_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
}

# WHY:        Sustained high CPU is the earliest sign of missing indexes or connection storms.
# DEPENDS:    Depends on the DB instance.
# GOES WRONG: CPU alone misses connection exhaustion: also watch DatabaseConnections.
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${local.name}-rds-cpu-high"
  alarm_description   = "RDS CPU above 80% for 15 minutes: slow queries, missing index, or undersized instance."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = local.out.rds.db_identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
}

# WHY:        Full storage makes RDS read-only: alarm well before that.
# DEPENDS:    Depends on the DB instance.
# GOES WRONG: Storage autoscaling without an alarm hides runaway growth cost.
resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${local.name}-rds-free-storage-low"
  alarm_description   = "RDS free storage below 2 GiB."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = local.out.rds.db_identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 2147483648
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
}

# WHY:        Throttled requests mean hot partitions or insufficient capacity.
# DEPENDS:    Depends on the table.
# GOES WRONG: On-demand tables can still throttle on a single hot key.
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  alarm_name          = "${local.name}-dynamodb-throttled"
  alarm_description   = "Requests to the products table are being throttled."
  namespace           = "AWS/DynamoDB"
  metric_name         = "ThrottledRequests"
  dimensions          = { TableName = local.out.dynamodb.table_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
}

# ---------------------------------------------------------------------------------------------
# DASHBOARD
# ---------------------------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Orders queue: backlog and age"
          region = var.region
          view   = "timeSeries"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.out.sqs.orders_queue_name],
            [".", "ApproximateAgeOfOldestMessage", ".", ".", { yAxis = "right" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Dead-letter queues"
          region = var.region
          view   = "timeSeries"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.out.sqs.dlq_name],
            [".", ".", ".", local.out.events.events_dlq_name],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "RDS CPU and connections"
          region = var.region
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", local.out.rds.db_identifier],
            [".", "DatabaseConnections", ".", ".", { yAxis = "right" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Lambda notifier"
          region = var.region
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", local.out.lambda.lambda_function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", ".", { yAxis = "right" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "DynamoDB capacity and throttles"
          region = var.region
          view   = "timeSeries"
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", local.out.dynamodb.table_name],
            [".", "ConsumedWriteCapacityUnits", ".", "."],
            [".", "ThrottledRequests", ".", "."],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "EKS nodes CPU / memory (Container Insights)"
          region = var.region
          view   = "timeSeries"
          metrics = [
            ["ContainerInsights", "node_cpu_utilization", "ClusterName", local.cluster_name],
            [".", "node_memory_utilization", ".", "."],
          ]
        }
      },
    ]
  })
}
