# syntax=docker/dockerfile:1
# --- build stage: Node only exists here; it never ships ---------------------------------------------------------------
FROM node:22.12-alpine3.21 AS build
WORKDIR /app
ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION
COPY package.json build.js ./
COPY src ./src
RUN node --check src/static/app.js && npm run build

# --- runtime stage: nginx as a NON-ROOT user (the "unprivileged" image listens on 8080, not 80) -------------------------
FROM nginxinc/nginx-unprivileged:1.27.3-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
# nginx runs as uid 101 (non-root); the Kubernetes securityContext uses the same uid and a read-only root filesystem.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/health || exit 1
# nginx handles SIGQUIT for graceful shutdown (finish in-flight requests); the base image's STOPSIGNAL is SIGQUIT.
CMD ["nginx", "-g", "daemon off;"]
