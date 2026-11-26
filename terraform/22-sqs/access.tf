# ---------------------------------------------------------------------------------------------
# WHO MAY SEND / RECEIVE + CONFIG PUBLICATION
# ---------------------------------------------------------------------------------------------
# Producer and consumer get DIFFERENT rights (least privilege): order-service can only SEND, worker can only RECEIVE/DELETE.
# The queue is encrypted with the CMK, so senders need kms:GenerateDataKey and receivers need kms:Decrypt (constrained to SQS use).
# GOES WRONG: worker logs AccessDenied on ReceiveMessage = missing sqs:ReceiveMessage OR kms:Decrypt (two gates), or the role
# is attached to a different ServiceAccount name than the Deployment uses (USER_GUIDE failure test 30.x "Break SQS worker permissions").

data "terraform_remote_state" "pod_identity" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/08-pod-identity/terraform.tfstate"
    region = var.region
  }
}

locals {
  role_names   = data.terraform_remote_state.pod_identity.outputs.role_names
  data_key_arn = data.terraform_remote_state.kms.outputs.data_key_arn
}

data "aws_iam_policy_document" "producer" {
  statement {
    sid       = "SendOrders"
    actions   = ["sqs:SendMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
    resources = [aws_sqs_queue.orders.arn]
  }

  statement {
    sid       = "EncryptForQueue"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [local.data_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["sqs.${var.region}.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "consumer" {
  statement {
    sid = "ConsumeOrders"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [aws_sqs_queue.orders.arn]
  }

  statement {
    sid       = "DecryptForQueue"
    actions   = ["kms:Decrypt"]
    resources = [local.data_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["sqs.${var.region}.amazonaws.com"]
    }
  }
}

# WHY:        Order service may only SendMessage to this queue.
# DEPENDS:    Depends on the order-service role.
# GOES WRONG: AccessDenied on SendMessage (the 'SQS permission' failure test) = this policy or missing kms:GenerateDataKey.
resource "aws_iam_role_policy" "producer" {
  name   = "sqs-send-orders"
  role   = local.role_names["order-service"]
  policy = data.aws_iam_policy_document.producer.json
}

# WHY:        Worker may only Receive/Delete/ChangeVisibility on this queue.
# DEPENDS:    Depends on the worker role.
# GOES WRONG: Missing DeleteMessage = messages reappear after the visibility timeout and are processed repeatedly.
resource "aws_iam_role_policy" "consumer" {
  name   = "sqs-consume-orders"
  role   = local.role_names["worker"]
  policy = data.aws_iam_policy_document.consumer.json
}

# WHY:        Publishes the queue URL for the app config.
# DEPENDS:    Read by deploy scripts.
# GOES WRONG: URL changes if the queue is recreated: re-run the deploy script.
resource "aws_ssm_parameter" "orders_queue_url" {
  name  = "${local.ssm_prefix}/sqs/orders_queue_url"
  type  = "String"
  value = aws_sqs_queue.orders.url
}
