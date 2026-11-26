"""Configuration loader (copy of product-service/app/settings.py so each image is self-contained).

Config contract: Terraform folders (15-s3, 19-rds, 20-dynamodb, 21-elasticache, 22-sqs, 24-eventbridge) write non-secret endpoints to SSM Parameter Store under SSM_PREFIX
(e.g. /cloudcart/lab). The pod reads them at startup with its Pod Identity credentials, so manifests/images carry no
environment-specific values. Environment variables override SSM (handy for local development).
"""
import logging
import os
import time

import boto3
from botocore.exceptions import BotoCoreError, ClientError

log = logging.getLogger("cloudcart.settings")


class Settings:
    def __init__(self) -> None:
        self._values: dict[str, str] = {}
        self.loaded = False

    def load(self, attempts: int = 8) -> None:
        """Load parameters from SSM. Retries because credentials/network can lag a few seconds behind pod start."""
        prefix = os.environ.get("SSM_PREFIX", "").rstrip("/")
        if not prefix:
            self.loaded = True
            return
        delay = 1.0
        for attempt in range(1, attempts + 1):
            try:
                ssm = boto3.client("ssm")
                values: dict[str, str] = {}
                for page in ssm.get_paginator("get_parameters_by_path").paginate(
                    Path=prefix, Recursive=True, WithDecryption=True
                ):
                    for param in page["Parameters"]:
                        values[param["Name"][len(prefix) + 1 :]] = param["Value"]
                if not values:
                    raise RuntimeError(f"no parameters found under {prefix}")
                self._values = values
                self.loaded = True
                log.info("loaded %d parameters from %s", len(values), prefix)
                return
            except (BotoCoreError, ClientError, RuntimeError) as exc:
                log.warning("config load attempt %d/%d failed: %s", attempt, attempts, exc)
                time.sleep(delay)
                delay = min(delay * 2, 15)
        raise RuntimeError(f"could not load configuration from SSM prefix {prefix}")

    def get(self, key: str, env: str | None = None, default: str | None = None) -> str | None:
        if env and os.environ.get(env):
            return os.environ[env]
        return self._values.get(key, default)

    def require(self, key: str, env: str | None = None) -> str:
        value = self.get(key, env)
        if value is None:
            raise RuntimeError(f"missing configuration key {key}")
        return value


settings = Settings()
