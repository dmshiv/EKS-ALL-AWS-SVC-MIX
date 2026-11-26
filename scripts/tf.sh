#!/usr/bin/env bash
# Safe wrapper around terraform for ONE folder. It NEVER applies automatically:
#   - `apply` re-plans, shows the plan, and requires you to TYPE the folder name before anything changes.
#   - `destroy` prints a DESTRUCTIVE banner and requires typing "destroy <folder>".
#
#   scripts/tf.sh <folder> <validate|init|plan|apply|output|destroy>
#   e.g.  scripts/tf.sh 01-vpc plan
#
# WORKFLOW per folder (the prompt's strict order):
#   dependency check -> fmt -> init -> validate -> plan -> (human reviews) -> apply -> verify (scripts/verify.sh)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
folder="${1:-}"; action="${2:-}"
[[ -n "$folder" && -n "$action" ]] && shift 2 || { sed -n '2,12p' "$0"; exit 2; }
folder="${folder%/}"
dir="$ROOT/terraform/$folder"
[[ -d "$dir" ]] || { echo "ERROR: no such folder: $dir" >&2; exit 2; }

die() { echo "ERROR: $*" >&2; exit 1; }

# shellcheck disable=SC1091
source "$ROOT/scripts/env.sh" >/dev/null || die "AWS credentials invalid; authenticate first (aws sso login / AWS_PROFILE)."
bash "$ROOT/scripts/sync-common.sh" >/dev/null

# UPSTREAM FOLDERS are derived from the code itself (every terraform_remote_state key), so this list can never go stale.
upstream() {
  { grep -hoE '[0-9]{2}-[a-z0-9-]+/terraform\.tfstate' "$dir"/*.tf 2>/dev/null | sed 's#/terraform.tfstate##'
    grep -hE '^[[:space:]]+[a-z0-9_]+[[:space:]]*=[[:space:]]*"[0-9]{2}-[a-z0-9-]+"' "$dir"/data.tf 2>/dev/null | sed -E 's/.*"([0-9]{2}-[a-z0-9-]+)".*/\1/'
  } | grep -v "^${folder}$" | sort -u || true
}

# Verifies BEFORE running: the state bucket exists, every upstream folder has a state object, and that state exports outputs.
check_dependencies() {
  [[ "$folder" == 00-bootstrap ]] && return 0
  echo "== dependency check for $folder"
  aws s3api head-bucket --bucket "$TF_STATE_BUCKET" 2>/dev/null \
    || die "state bucket $TF_STATE_BUCKET not found. Apply 00-bootstrap first."
  local up key n
  for up in $(upstream); do
    key="$ENVIRONMENT/$up/terraform.tfstate"
    aws s3api head-object --bucket "$TF_STATE_BUCKET" --key "$key" >/dev/null 2>&1 \
      || die "upstream state missing: s3://$TF_STATE_BUCKET/$key  -> apply $up first."
    n="$(aws s3 cp "s3://$TF_STATE_BUCKET/$key" - 2>/dev/null | jq '.outputs | length')"
    [[ "${n:-0}" -gt 0 ]] || die "upstream $up has a state file but NO outputs (was it destroyed?)."
    echo "   ok  $up ($n outputs)"
  done
}

tf_init() {
  cd "$dir"
  if [[ "$folder" == 00-bootstrap ]]; then
    terraform init -input=false
  else
    terraform init -input=false -reconfigure \
      -backend-config="bucket=$TF_STATE_BUCKET" \
      -backend-config="key=$ENVIRONMENT/$folder/terraform.tfstate" \
      -backend-config="region=$AWS_REGION" \
      -backend-config="use_lockfile=true" \
      -backend-config="encrypt=true"
  fi
}

varfile_args() {
  local f="$ROOT/envs/$ENVIRONMENT/$folder.tfvars"
  [[ -f "$f" ]] && echo "-var-file=$f" || true
}

tf_validate() {
  cd "$dir"
  terraform fmt -check -diff || die "terraform fmt needed: run 'terraform fmt' in $dir"
  terraform validate
}

case "$action" in
  validate)
    check_dependencies; tf_init; tf_validate ;;
  init)
    check_dependencies; tf_init ;;
  plan)
    check_dependencies; tf_init; tf_validate
    # shellcheck disable=SC2046
    terraform plan -input=false -out=tfplan $(varfile_args) ;;
  apply)
    check_dependencies; tf_init; tf_validate
    # shellcheck disable=SC2046
    terraform plan -input=false -out=tfplan $(varfile_args)
    echo
    echo ">>> REVIEW THE PLAN ABOVE. Applying changes REAL AWS resources (and may cost money)."
    read -r -p "Type the folder name ($folder) to apply, anything else aborts: " answer
    [[ "$answer" == "$folder" ]] || die "aborted, nothing applied."
    terraform apply -input=false tfplan
    echo ">>> apply finished. Running verification (waits for resources to become ready)..."
    bash "$ROOT/scripts/verify.sh" "$folder" ;;
  output)
    check_dependencies; tf_init >/dev/null; terraform output ;;
  destroy)
    echo "!!! DESTRUCTIVE ACTION: this will DELETE every resource managed by $folder (state: $ENVIRONMENT/$folder)."
    echo "!!! Check the folder README 'Cleanup' section for data-loss warnings and the required destroy ORDER."
    read -r -p "Type 'destroy $folder' to continue: " answer
    [[ "$answer" == "destroy $folder" ]] || die "aborted, nothing destroyed."
    tf_init
    # shellcheck disable=SC2046
    terraform destroy $(varfile_args) ;;
  upstream)
    upstream ;;
  *)
    die "unknown action '$action' (validate|init|plan|apply|output|destroy|upstream)" ;;
esac
