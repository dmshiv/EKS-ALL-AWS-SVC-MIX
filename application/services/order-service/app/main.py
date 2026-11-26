"""CloudCart order-service: PostgreSQL (RDS) for orders, SQS for asynchronous processing.

DB password: NEVER in env/Helm/Git. The RDS-managed secret in Secrets Manager is read at startup with Pod Identity credentials.
Flow: POST /orders -> INSERT status=PENDING -> SQS SendMessage -> (worker) -> status=PROCESSED.
"""
import json
import logging
import os
import uuid
from contextlib import asynccontextmanager

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import FastAPI, HTTPException
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb
from psycopg_pool import ConnectionPool
from pydantic import BaseModel, Field

from app.settings import settings

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("cloudcart.order")

state: dict = {"pool": None, "sqs": None, "queue_url": None}

SCHEMA = """
CREATE TABLE IF NOT EXISTS orders (
    id          uuid PRIMARY KEY,
    customer    text NOT NULL,
    items       jsonb NOT NULL,
    total       numeric(12,2) NOT NULL,
    status      text NOT NULL DEFAULT 'PENDING',
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
)
"""


class OrderItem(BaseModel):
    product_id: str = Field(min_length=1, max_length=64)
    quantity: int = Field(gt=0, le=1000)
    unit_price: float = Field(gt=0)


class OrderIn(BaseModel):
    customer: str = Field(min_length=1, max_length=200)
    items: list[OrderItem] = Field(min_length=1, max_length=100)


def _conninfo() -> str:
    secret = json.loads(
        boto3.client("secretsmanager").get_secret_value(SecretId=settings.require("rds/secret_arn", "DB_SECRET_ARN"))["SecretString"]
    )
    # sslmode=require: the instance enforces TLS (rds.force_ssl=1), plaintext connections are rejected.
    return (
        f"host={settings.require('rds/host', 'DB_HOST')} port={settings.get('rds/port', 'DB_PORT', '5432')} "
        f"dbname={settings.require('rds/dbname', 'DB_NAME')} user={secret['username']} password={secret['password']} "
        f"sslmode=require connect_timeout=5"
    )


@asynccontextmanager
async def lifespan(_: FastAPI):
    settings.load()
    pool = ConnectionPool(_conninfo(), min_size=1, max_size=5, open=False, kwargs={"row_factory": dict_row})
    pool.open(wait=True, timeout=30)
    with pool.connection() as conn:
        conn.execute(SCHEMA)
    state["pool"] = pool
    state["sqs"] = boto3.client("sqs")
    state["queue_url"] = settings.require("sqs/orders_queue_url", "ORDERS_QUEUE_URL")
    log.info("order-service started")
    yield
    pool.close()


app = FastAPI(title="CloudCart order-service", lifespan=lifespan)


@app.get("/health")
def health():
    """Liveness: process is up; deliberately does not touch the database."""
    return {"status": "ok"}


@app.get("/ready")
def ready():
    """Readiness: can reach PostgreSQL (network + security group + TLS + credentials)."""
    try:
        with state["pool"].connection(timeout=3) as conn:
            conn.execute("SELECT 1")
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"database not ready: {exc}")
    return {"status": "ready"}


@app.post("/orders", status_code=202)
def create_order(order: OrderIn):
    order_id = uuid.uuid4()
    total = round(sum(i.quantity * i.unit_price for i in order.items), 2)
    try:
        with state["pool"].connection() as conn:
            conn.execute(
                "INSERT INTO orders (id, customer, items, total, status) VALUES (%s, %s, %s, %s, 'PENDING')",
                (order_id, order.customer, Jsonb([i.model_dump() for i in order.items]), total),
            )
    except Exception as exc:
        log.error("db insert failed: %s", exc)
        raise HTTPException(status_code=503, detail="order database unavailable")
    try:
        state["sqs"].send_message(
            QueueUrl=state["queue_url"],
            MessageBody=json.dumps({"order_id": str(order_id)}),
        )
    except (BotoCoreError, ClientError) as exc:
        # The order exists but will not be processed: record it so an operator/reconciler can retry.
        log.error("sqs send failed for %s: %s", order_id, exc)
        with state["pool"].connection() as conn:
            conn.execute("UPDATE orders SET status='QUEUE_FAILED', updated_at=now() WHERE id=%s", (order_id,))
        raise HTTPException(status_code=502, detail="order saved but could not be queued")
    return {"order_id": str(order_id), "status": "PENDING", "total": total}


@app.get("/orders/{order_id}")
def get_order(order_id: uuid.UUID):
    try:
        with state["pool"].connection() as conn:
            row = conn.execute("SELECT * FROM orders WHERE id=%s", (order_id,)).fetchone()
    except Exception as exc:
        log.error("db read failed: %s", exc)
        raise HTTPException(status_code=503, detail="order database unavailable")
    if not row:
        raise HTTPException(status_code=404, detail="order not found")
    row["id"] = str(row["id"])
    row["total"] = float(row["total"])
    row["created_at"] = row["created_at"].isoformat()
    row["updated_at"] = row["updated_at"].isoformat()
    return row
