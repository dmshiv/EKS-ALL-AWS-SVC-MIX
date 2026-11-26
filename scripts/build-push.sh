#!/usr/bin/env bash
# Build, SCAN, tag and push the four CloudCart images to ECR with an IMMUTABLE tag.
#   scripts/build-push.sh                 # tag = v<version>-<git short sha>   (git sha when available, else a timestamp)
#   scripts/build-push.sh v1.0.1          # explicit version, still suffixed with the sha
#
# THE IMAGE LIFECYCLE (every step explained):
#   source -> Dockerfile -> `docker build` -> image in the LOCAL docker image store (docker images) -> tag with the ECR repository URL
#   -> scan -> `aws ecr get-login-password | docker login` (STS-based, valid ~12 hours, uses your CURRENT AWS credentials; written to ~/.docker/config.json)
#   -> `docker push` (layers uploaded over HTTPS to ECR; layers already present are skipped) -> ECR stores the image
#   (tag immutability: pushing the same tag again FAILS, which is the point) -> later the node's kubelet pulls it with the NODE role.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib.sh"
need docker; need jq

VERSION="${1:-v1.0.0}"
SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)"
TAG="${VERSION}-${SHA}"
REGISTRY="$(state_out 04-ecr registry_url)"

echo "== registry: $REGISTRY   tag: $TAG"
echo "== docker login to ECR (token from: aws ecr get-login-password; no password is stored in Git)"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY"

for svc in frontend product-service order-service worker; do
  image="$REGISTRY/cloudcart-$svc:$TAG"
  echo; echo "== build $svc"
  docker build --pull --build-arg APP_VERSION="$TAG" -t "$image" "$ROOT/application/services/$svc"

  # LOCAL SCAN (optional but recommended): fails the script on HIGH/CRITICAL findings when trivy is installed.
  if command -v trivy >/dev/null 2>&1; then
    echo "== trivy scan $svc"; trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed "$image"
  else
    echo "   (trivy not installed: skipping local scan; ECR basic scanning still runs on push)"
  fi

  echo "== push $svc"
  docker push "$image"
done

echo; echo "Pushed tag: $TAG"
echo "Deploy it:  IMAGE_TAG=$TAG scripts/deploy-app.sh"
echo "ECR scan results: aws ecr describe-image-scan-findings --repository-name cloudcart-<svc> --image-id imageTag=$TAG"
