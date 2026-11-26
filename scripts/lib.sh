#!/usr/bin/env bash
# Shared helpers for the deploy scripts. Source it:  source scripts/lib.sh
# READ-ONLY access to Terraform results: values are read straight from the remote state objects in S3, so no `terraform init` is needed
# and nothing is ever changed.
set -euo pipefail
LIB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$LIB_ROOT/scripts/env.sh" >/dev/null

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' is required but not installed." >&2; exit 1; }; }

# state_out <folder> <output-name>   -> prints the output value (raw string, or JSON for lists/maps)
state_out() {
  local folder="$1" name="$2" json
  json="$(aws s3 cp "s3://$TF_STATE_BUCKET/$ENVIRONMENT/$folder/terraform.tfstate" - 2>/dev/null)" \
    || { echo "ERROR: state of $folder not found. Apply that folder first (scripts/tf.sh $folder apply)." >&2; return 1; }
  echo "$json" | jq -er --arg n "$name" '.outputs[$n].value | if type=="string" then . else tojson end'
}

# like state_out but prints "" instead of failing when the output is missing/empty (optional features such as DNS)
state_out_opt() { state_out "$@" 2>/dev/null || true; }
