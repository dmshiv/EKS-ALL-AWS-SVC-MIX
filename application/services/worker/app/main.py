"""CloudCart worker: SQS consumer.

Receive -> process -> delete. A message is deleted ONLY after successful processing; on any exception it is left alone and
becomes visible again after the visibility timeout. After maxReceiveCount failed receives SQS moves it to the DLQ.
Because SQS Standard is at-least-once, processing is IDEMPOTENT (an already-processed order is a no-op success).
"""
import json
import logging
import os
import signal
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from app.settings import settings

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("cloudcart.worker")

stop = threading.Event()
health = {"ready": False}


def _conninfo() -> str:
    secret = json.loads(
        boto3.client("secretsmanager").get_secret_value(SecretId=settings.require("rds/secret_arn", "DB_SECRET_ARN"))["SecretString"]
    )
    return (
        f"host={settings.require('rds/host', 'DB_HOST')} port={settings.get('rds/port', 'DB_PORT', '5432')} "
        f"dbname={settings.require('rds/dbname', 'DB_NAME')} user={secret['username']} password={secret['password']} "
        f"sslmode=require connect_timeout=5"
    )


class Probe(BaseHTTPRequestHandler):
    """Tiny HTTP endpoint so Kubernetes can probe the worker like the other services."""

    def do_GET(self):  # noqa: N802
        ok = self.path == "/health" or (self.path == "/ready" and health["ready"])
        self.send_response(200 if ok else 503)
        self.end_headers()
        self.wfile.write(b'{"status":"ok"}' if ok else b'{"status":"not ready"}')

    def log_message(self, *_):
        pass


def process(body: dict, pool: ConnectionPool, events) -> None:
    if os.environ.get("ALLOW_FAIL_INJECTION") == "true" and body.get("simulate") == "fail":
        raise RuntimeError("simulated failure (failure-injection test)")
    order_id = body["order_id"]
    with pool.connection() as conn:
        row = conn.execute(
            "UPDATE orders SET status='PROCESSED', updated_at=now() WHERE id=%s AND status='PENDING' RETURNING customer, total",
            (order_id,),
        ).fetchone()
        if row is None:
            existing = conn.execute("SELECT status FROM orders WHERE id=%s", (order_id,)).fetchone()
            if existing is None:
                raise RuntimeError(f"order {order_id} does not exist")
            log.info("order %s already %s, nothing to do (idempotent)", order_id, existing["status"])
            return
    result = events.put_events(
        Entries=[
            {
                "EventBusName": settings.require("events/bus_name", "EVENT_BUS"),
                "Source": "cloudcart.orders",
                "DetailType": "OrderProcessed",
                "Detail": json.dumps(
                    {"order_id": order_id, "status": "PROCESSED", "customer": row["customer"], "total": float(row["total"])}
                ),
            }
        ]
    )
    if result.get("FailedEntryCount"):
        raise RuntimeError(f"put_events failed: {result['Entries']}")
    log.info("order %s processed and event published", order_id)


def main() -> None:
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    server = HTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8080"))), Probe)
    threading.Thread(target=server.serve_forever, daemon=True).start()

    settings.load()
    pool = ConnectionPool(_conninfo(), min_size=1, max_size=3, open=False, kwargs={"row_factory": dict_row})
    pool.open(wait=True, timeout=30)
    sqs = boto3.client("sqs")
    events = boto3.client("events")
    queue_url = settings.require("sqs/orders_queue_url", "ORDERS_QUEUE_URL")
    health["ready"] = True
    log.info("worker started, polling %s", queue_url)

    while not stop.is_set():
        try:
            resp = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=5, WaitTimeSeconds=20)
        except (BotoCoreError, ClientError) as exc:
            log.error("receive failed (IAM/network?): %s", exc)
            time.sleep(5)
            continue
        for msg in resp.get("Messages", []):
            try:
                process(json.loads(msg["Body"]), pool, events)
                sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=msg["ReceiptHandle"])
            except Exception as exc:
                # Not deleted on purpose: the message returns after the visibility timeout; SQS counts the attempt toward the DLQ.
                log.error("message %s failed (will be retried / DLQ): %s", msg.get("MessageId"), exc)
    log.info("SIGTERM received, finishing and exiting")
    health["ready"] = False
    pool.close()


if __name__ == "__main__":
    main()
