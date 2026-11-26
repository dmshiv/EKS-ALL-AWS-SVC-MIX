"""CloudCart order notifier: EventBridge (OrderProcessed) -> SNS.

Invoked asynchronously by EventBridge. Raising an exception makes EventBridge retry
(retry_policy in Terraform) and finally park the event in the events DLQ.
"""
import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# Created outside the handler so warm invocations reuse the connection.
sns = boto3.client("sns")
TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


def handler(event, context):
    detail = event.get("detail", {})
    order_id = detail.get("order_id", "unknown")
    logger.info("received %s for order %s", event.get("detail-type"), order_id)

    message = {
        "order_id": order_id,
        "status": detail.get("status", "PROCESSED"),
        "customer": detail.get("customer"),
        "total": detail.get("total"),
    }
    response = sns.publish(
        TopicArn=TOPIC_ARN,
        Subject=f"CloudCart order {order_id} processed",
        Message=json.dumps(message),
        MessageAttributes={"event_type": {"DataType": "String", "StringValue": "OrderProcessed"}},
    )
    logger.info("published to SNS message_id=%s", response["MessageId"])
    return {"published": True, "message_id": response["MessageId"]}
