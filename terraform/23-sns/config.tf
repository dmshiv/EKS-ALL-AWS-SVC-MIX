# Config publication (see 18-parameter-store). The notifier Lambda (25-lambda) receives the topic ARN as an environment variable
# straight from this folder's output; the SSM parameter is for any pod that later needs to publish.
resource "aws_ssm_parameter" "topic_arn" {
  name  = "${local.ssm_prefix}/sns/topic_arn"
  type  = "String"
  value = aws_sns_topic.orders.arn
}
