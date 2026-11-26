#!/usr/bin/env bash
# Copies terraform/_common/*.tf into every numbered Terraform folder (except 00-bootstrap, which
# has its own files because it runs on LOCAL state before the S3 backend exists).
# Why a script and not a shared module? Provider pins, backend blocks and `terraform {}` blocks
# cannot live in a module; they must exist in every root module.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/terraform"

# Folders that talk to the Kubernetes API additionally get _common_k8s/*.tf (kubernetes + helm providers, cluster auth).
K8S_FOLDERS=(12-karpenter 26-route53 28-load-balancer-controller 41-autoscaling 42-network-policies 47-gitops)

for dir in [0-9][0-9]-*/; do
  dir="${dir%/}"
  [[ "$dir" == 00-bootstrap ]] && continue
  for f in _common/*.tf; do
    cp "$f" "$dir/$(basename "$f")"
  done
done

for dir in "${K8S_FOLDERS[@]}"; do
  [[ -d "$dir" ]] || continue
  for f in _common_k8s/*.tf; do
    cp "$f" "$dir/$(basename "$f")"
  done
done

# Terraform allows ONLY ONE required_providers block per module, so the extra provider pins are merged into versions.tf here.
declare -A EXTRA
for dir in "${K8S_FOLDERS[@]}"; do
  EXTRA[$dir]=$'    kubernetes = {\n      source  = "hashicorp/kubernetes"\n      version = "~> 2.38"\n    }\n    helm = {\n      source  = "hashicorp/helm"\n      version = "~> 2.17"\n    }\n'
done
EXTRA[17-secrets-manager]=$'    random = {\n      source  = "hashicorp/random"\n      version = "~> 3.6"\n    }\n'
EXTRA[25-lambda]=$'    archive = {\n      source  = "hashicorp/archive"\n      version = "~> 2.7"\n    }\n'
for dir in [0-9][0-9]-*/; do
  dir="${dir%/}"
  [[ "$dir" == 00-bootstrap ]] && continue
  awk -v extra="${EXTRA[$dir]:-}" '/#EXTRA_PROVIDERS/ { printf "%s", extra; next } { print }' "$dir/versions.tf" > "$dir/versions.tf.tmp" && mv "$dir/versions.tf.tmp" "$dir/versions.tf"
done
echo "synced _common into $(ls -d [0-9][0-9]-*/ | grep -vc '^00-') folders and _common_k8s into ${#K8S_FOLDERS[@]} folders"
