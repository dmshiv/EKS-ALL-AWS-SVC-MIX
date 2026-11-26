#!/usr/bin/env bash
# Offline static validation of every Terraform folder: fmt check + init (no backend) + validate.
# Needs NO AWS credentials. Run before every commit/apply.
#   scripts/validate-all.sh            # all folders
#   scripts/validate-all.sh 06-eks     # one folder
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"
export TF_VAR_state_bucket="${TF_VAR_state_bucket:-validate-only}"

bash "$ROOT/scripts/sync-common.sh" >/dev/null
cd "$ROOT/terraform"

targets=("$@")
[[ ${#targets[@]} -eq 0 ]] && targets=($(ls -d [0-9][0-9]-*/ | tr -d /))

fail=0
for d in "${targets[@]}"; do
  [[ -d "$d" ]] || { echo "SKIP $d (no such folder)"; continue; }
  ls "$d"/*.tf >/dev/null 2>&1 || { echo "SKIP $d (no .tf files yet)"; continue; }
  out=$( (cd "$d" && terraform fmt -check -diff -recursive >/dev/null 2>&1 || echo "FMT-NEEDED"; \
          terraform init -backend=false -input=false -no-color >/dev/null 2>&1 || echo "INIT-FAILED"; \
          terraform validate -no-color 2>&1) )
  if echo "$out" | grep -q "Success!"; then
    note=""; echo "$out" | grep -q FMT-NEEDED && note=" (needs terraform fmt)"
    echo "OK    $d$note"
  else
    echo "FAIL  $d"; echo "$out" | sed 's/^/      /'; fail=1
  fi
done
exit $fail
