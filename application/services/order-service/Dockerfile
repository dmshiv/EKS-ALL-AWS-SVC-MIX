# syntax=docker/dockerfile:1
# --- build stage: compile/install dependencies; none of this ships in the final image -------------------------------
FROM python:3.12.8-slim-bookworm AS builder
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build
COPY requirements.txt .
# Pinned versions (requirements.txt) => reproducible builds. --prefix keeps the install relocatable.
RUN pip install --prefix=/install -r requirements.txt

# --- runtime stage: small, non-root ---------------------------------------------------------------------------------
FROM python:3.12.8-slim-bookworm
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PORT=8080
# Fixed non-root uid/gid (10001) matches the Kubernetes securityContext and the EFS access point.
RUN groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid 10001 --no-create-home app
COPY --from=builder /install /usr/local
WORKDIR /srv
COPY --chown=10001:10001 app ./app
USER 10001:10001
EXPOSE 8080
# Used by `docker run`; Kubernetes uses its own probes (/health liveness, /ready readiness).
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request,os;urllib.request.urlopen('http://127.0.0.1:'+os.environ.get('PORT','8080')+'/health',timeout=2)" || exit 1
# exec form: uvicorn is PID 1 and receives SIGTERM, so it drains requests and exits cleanly when the pod is stopped.
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--timeout-graceful-shutdown", "20"]
