"""CloudCart product-service: DynamoDB catalog + S3 images + optional Redis cache.

AWS credentials come from EKS Pod Identity (container credential endpoint). There are NO access keys in this code or image.
The cache is OPTIONAL: if Redis is down the API still works (fail open), only slower.
"""
import json
import logging
import os
from contextlib import asynccontextmanager
from decimal import Decimal

import boto3
import redis
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import FastAPI, File, HTTPException, UploadFile
from pydantic import BaseModel, Field

from app.settings import settings

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("cloudcart.product")

state: dict = {"table": None, "s3": None, "bucket": None, "cache": None, "ttl": 60}


class ProductIn(BaseModel):
    product_id: str = Field(min_length=1, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    name: str = Field(min_length=1, max_length=200)
    price: float = Field(gt=0)
    category: str = Field(min_length=1, max_length=64)


def _json_safe(item: dict) -> dict:
    return {k: (float(v) if isinstance(v, Decimal) else v) for k, v in item.items()}


def _connect_cache() -> None:
    host = settings.get("redis/host", "REDIS_HOST")
    if not host:
        return
    try:
        secret_arn = settings.get("redis/secret_arn", "REDIS_SECRET_ARN")
        password = None
        if secret_arn:
            sm = boto3.client("secretsmanager")
            password = json.loads(sm.get_secret_value(SecretId=secret_arn)["SecretString"])["auth_token"]
        client = redis.Redis(
            host=host,
            port=int(settings.get("redis/port", "REDIS_PORT", "6379")),
            password=password,
            ssl=True,  # transit encryption is enabled on the replication group
            socket_timeout=0.5,
            socket_connect_timeout=0.5,
        )
        client.ping()
        state["cache"] = client
        log.info("redis cache connected")
    except Exception as exc:  # cache must never prevent the service from starting
        log.warning("redis unavailable, running without cache: %s", exc)


@asynccontextmanager
async def lifespan(_: FastAPI):
    settings.load()
    ddb = boto3.resource("dynamodb")
    state["table"] = ddb.Table(settings.require("dynamodb/table_name", "DDB_TABLE"))
    state["bucket"] = settings.require("s3/bucket", "S3_BUCKET")
    state["s3"] = boto3.client("s3", config=Config(signature_version="s3v4"))
    state["ttl"] = int(settings.get("app/cache_ttl_seconds", "CACHE_TTL", "60"))
    _connect_cache()
    yield
    log.info("shutting down")


app = FastAPI(title="CloudCart product-service", lifespan=lifespan)


def _cache_get(key: str):
    cache = state["cache"]
    if not cache:
        return None
    try:
        raw = cache.get(key)
        return json.loads(raw) if raw else None
    except Exception as exc:
        log.warning("cache get failed (fail open): %s", exc)
        return None


def _cache_set(key: str, value) -> None:
    cache = state["cache"]
    if not cache:
        return
    try:
        cache.setex(key, state["ttl"], json.dumps(value))
    except Exception as exc:
        log.warning("cache set failed (fail open): %s", exc)


def _cache_delete(*keys: str) -> None:
    cache = state["cache"]
    if not cache:
        return
    try:
        cache.delete(*keys)
    except Exception as exc:
        log.warning("cache delete failed (fail open): %s", exc)


@app.get("/health")
def health():
    """Liveness: the process is up. Must NOT check dependencies (a DB outage would restart healthy pods)."""
    return {"status": "ok"}


@app.get("/ready")
def ready():
    """Readiness: can this pod serve traffic? Checks DynamoDB access (IAM + network). Redis is optional."""
    try:
        state["table"].load()
    except (BotoCoreError, ClientError, AttributeError) as exc:
        raise HTTPException(status_code=503, detail=f"dynamodb not ready: {exc}")
    return {"status": "ready", "cache": "up" if state["cache"] else "down"}


@app.get("/products")
def list_products():
    cached = _cache_get("products:all")
    if cached is not None:
        return {"source": "cache", "items": cached}
    try:
        items = [_json_safe(i) for i in state["table"].scan(Limit=100)["Items"]]
    except (BotoCoreError, ClientError) as exc:
        log.error("dynamodb scan failed: %s", exc)
        raise HTTPException(status_code=502, detail="catalog unavailable")
    _cache_set("products:all", items)
    return {"source": "dynamodb", "items": items}


@app.get("/products/{product_id}")
def get_product(product_id: str):
    key = f"product:{product_id}"
    cached = _cache_get(key)
    if cached is not None:
        return {"source": "cache", "item": cached}
    try:
        item = state["table"].get_item(Key={"product_id": product_id}).get("Item")
    except (BotoCoreError, ClientError) as exc:
        log.error("dynamodb get failed: %s", exc)
        raise HTTPException(status_code=502, detail="catalog unavailable")
    if not item:
        raise HTTPException(status_code=404, detail="product not found")
    item = _json_safe(item)
    _cache_set(key, item)
    return {"source": "dynamodb", "item": item}


@app.post("/products", status_code=201)
def create_product(product: ProductIn):
    item = {**product.model_dump(), "price": Decimal(str(product.price))}
    try:
        state["table"].put_item(Item=item, ConditionExpression="attribute_not_exists(product_id)")
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            raise HTTPException(status_code=409, detail="product already exists")
        log.error("dynamodb put failed: %s", exc)
        raise HTTPException(status_code=502, detail="catalog unavailable")
    _cache_delete("products:all")
    return _json_safe(item)


@app.post("/products/{product_id}/image", status_code=201)
async def upload_image(product_id: str, file: UploadFile = File(...)):
    if file.content_type not in {"image/png", "image/jpeg", "image/webp"}:
        raise HTTPException(status_code=415, detail="only png/jpeg/webp images are accepted")
    data = await file.read()
    if len(data) > 2 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="image larger than 2 MiB")
    key = f"products/{product_id}/{os.path.basename(file.filename or 'image')}"
    try:
        # Bucket default encryption (SSE-KMS with the data CMK) applies; the pod role needs s3:PutObject AND kms:GenerateDataKey.
        state["s3"].put_object(Bucket=state["bucket"], Key=key, Body=data, ContentType=file.content_type)
    except (BotoCoreError, ClientError) as exc:
        log.error("s3 put failed: %s", exc)
        raise HTTPException(status_code=502, detail=f"image storage error: {exc}")
    return {"key": key, "bytes": len(data)}


@app.get("/products/{product_id}/image-url")
def image_url(product_id: str, key: str):
    if not key.startswith(f"products/{product_id}/"):
        raise HTTPException(status_code=400, detail="key does not belong to this product")
    url = state["s3"].generate_presigned_url(
        "get_object", Params={"Bucket": state["bucket"], "Key": key}, ExpiresIn=300
    )
    return {"url": url, "expires_in": 300}
