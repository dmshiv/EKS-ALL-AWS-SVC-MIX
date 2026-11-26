#!/usr/bin/env bash
# Deploy CloudCart with Helm. Values come from terraform/99-capstone (output helm_values) read from state: nothing is typed by hand.
#   IMAGE_TAG=v1.0.0-3f2a1c9 scripts/deploy-app.sh
#
# ORDER (see scripts/execution-order.txt): infrastructure folders applied -> images pushed (build-push.sh) -> this script.
# `helm upgrade --install --atomic --wait`: waits until Deployments are Ready; if anything fails it ROLLS BACK automatically.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib.sh"
need helm; need kubectl; need jq

TAG="${IMAGE_TAG:?set IMAGE_TAG to the immutable tag printed by scripts/build-push.sh (never latest)}"
[[ "$TAG" != "latest" ]] || { echo "ERROR: refusing to deploy :latest" >&2; exit 1; }

echo "== kubeconfig  (aws eks update-kubeconfig writes ~/.kube/config using an 'aws eks get-token' exec plugin; no static token)"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null

echo "== namespaces + baseline"
kubectl apply -f "$ROOT/kubernetes/namespaces/"

echo "== reading helm values from terraform state (99-capstone)"
VALUES_FILE="$(mktemp)"; trap 'rm -f "$VALUES_FILE"' EXIT
state_out 99-capstone helm_values > "$VALUES_FILE" || { echo "Apply 99-capstone first (it only reads state)."; exit 1; }
jq --arg tag "$TAG" '.global.imageTag = $tag' "$VALUES_FILE" > "$VALUES_FILE.new" && mv "$VALUES_FILE.new" "$VALUES_FILE"

echo "== helm lint"
helm lint "$ROOT/helm/cloudcart" -f "$VALUES_FILE"

echo "== helm upgrade --install"
helm upgrade --install cloudcart "$ROOT/helm/cloudcart" \
  --namespace cloudcart --create-namespace \
  -f "$VALUES_FILE" \
  --atomic --wait --timeout 15m

echo "== result"
kubectl -n cloudcart get deploy,pods,svc,hpa,ingress
echo "ALB hostname (appears after a few minutes):"
echo "  kubectl -n cloudcart get ingress cloudcart -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{\"\\n\"}'"
