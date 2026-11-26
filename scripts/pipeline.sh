#!/usr/bin/env bash
# One-command runner for the whole project: applies or destroys the Terraform folders in dependency order with a live pipeline view.
#   scripts/pipeline.sh                          # interactive menu
#   scripts/pipeline.sh apply                    # asks which folders (default: all)
#   scripts/pipeline.sh apply 1-8                # folders by number (see the menu) or ranges, e.g. "1-8 12 20-25"
#   scripts/pipeline.sh apply all --yes          # no confirmation prompt (unattended)
#   scripts/pipeline.sh apply --confirm-each     # show each folder's plan summary and ask before its apply
#   scripts/pipeline.sh destroy all              # reverse order, K8s cleanup first, never touches 00-bootstrap
#   --no-hooks                                   # skip the Karpenter / image build / Helm deploy steps between folders
#
# Per folder (apply):  scripts/tf.sh <folder> plan (deps check, fmt check, init, validate, plan) -> terraform apply of that exact plan
#                      -> scripts/verify.sh <folder> (polls the real AWS resources). It stops at the first failure.
# Hook steps run in between:  after 12-karpenter -> deploy-karpenter.sh;  after 99-capstone -> build-push.sh then deploy-app.sh.
# Order comes from scripts/execution-order.txt (16-kms is applied right after 03). Locking stays ON (S3 lockfile).
# Logs: one file per step under /tmp/cloudcart-pipeline-*/ (path printed at the end and on failure).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ACTION="" SEL="" YES=0 EACH=0 HOOKS=1
for a in "$@"; do
  case "$a" in
    apply|destroy) ACTION="$a" ;;
    --yes) YES=1 ;;
    --confirm-each) EACH=1 ;;
    --no-hooks) HOOKS=0 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) SEL="$SEL $a" ;;
  esac
done

TTY=0; [[ -t 1 ]] && TTY=1
if (( TTY )); then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; CYAN=$'\033[0;36m'; WHITE=$'\033[1;37m'; GRAY=$'\033[0;90m'; NC=$'\033[0m'
else
  RED="" GREEN="" YELLOW="" CYAN="" WHITE="" GRAY="" NC=""
fi
die() { echo "${RED}ERROR:${NC} $*" >&2; exit 1; }

for c in terraform aws jq; do command -v "$c" >/dev/null 2>&1 || die "'$c' is required but not installed."; done
# shellcheck disable=SC1091
source "$ROOT/scripts/env.sh" >/dev/null || die "AWS credentials are not valid. Authenticate first (aws sts get-caller-identity must work)."

mapfile -t ORDER < <(grep -E '^[0-9]{2}-' "$ROOT/scripts/execution-order.txt")
[[ ${#ORDER[@]} -gt 0 ]] || die "scripts/execution-order.txt has no folders."

# ---------------------------------------------------------------- menu / selection
if [[ -z "$ACTION" ]]; then
  echo "1) Apply   (create infrastructure, order 00 -> 99)"
  echo "2) Destroy (tear down, reverse order)"
  read -r -p "Select (1-2): " c
  case "$c" in 1) ACTION=apply ;; 2) ACTION=destroy ;; *) die "invalid choice" ;; esac
fi

if [[ -z "${SEL// }" && $YES -eq 0 && -t 0 ]]; then
  echo; for i in "${!ORDER[@]}"; do printf '%3d. %s\n' $((i + 1)) "${ORDER[$i]}"; done
  read -r -p $'\nFolders (e.g. "1-8 12", or "all") [all]: ' SEL
fi

SELECTED=()
if [[ -z "${SEL// }" || "${SEL// }" == all ]]; then
  SELECTED=("${ORDER[@]}")
else
  declare -A want=()
  for tok in $SEL; do
    if [[ "$tok" =~ ^([0-9]+)-([0-9]+)$ ]]; then a="${BASH_REMATCH[1]}"; b="${BASH_REMATCH[2]}"
    elif [[ "$tok" =~ ^[0-9]+$ ]]; then a="$tok"; b="$tok"
    else die "invalid selection '$tok' (use numbers, ranges like 3-7, or all)"; fi
    (( a >= 1 && a <= b && b <= ${#ORDER[@]} )) || die "selection '$tok' is outside 1-${#ORDER[@]}"
    for ((i = a; i <= b; i++)); do want[$i]=1; done
  done
  for i in "${!ORDER[@]}"; do [[ -n "${want[$((i + 1))]:-}" ]] && SELECTED+=("${ORDER[$i]}"); done
fi
[[ ${#SELECTED[@]} -gt 0 ]] || die "nothing selected"

in_list() { local x="$1"; shift; local y; for y in "$@"; do [[ "$y" == "$x" ]] && return 0; done; return 1; }

# ---------------------------------------------------------------- build the run list (folders + hook steps)
RUN=()
if [[ "$ACTION" == apply ]]; then
  for f in "${SELECTED[@]}"; do
    RUN+=("$f")
    if (( HOOKS )); then
      [[ "$f" == 12-karpenter ]] && RUN+=("@karpenter-policy")
      [[ "$f" == 99-capstone ]] && RUN+=("@build-push" "@deploy-app")
    fi
  done
else
  for f in "${SELECTED[@]}"; do [[ "$f" == 00-bootstrap ]] || RUN=("$f" "${RUN[@]}"); done   # reverse, bootstrap bucket is never destroyed here
  if in_list 06-eks "${RUN[@]}" || in_list 12-karpenter "${RUN[@]}" || in_list 28-load-balancer-controller "${RUN[@]}"; then
    RUN=("@k8s-cleanup" "${RUN[@]}")
  fi
fi
[[ ${#RUN[@]} -gt 0 ]] || die "nothing to run (00-bootstrap is not destroyed by this script)"

# tools needed by the hook steps
if [[ "$ACTION" == apply ]]; then
  in_list @karpenter-policy "${RUN[@]}" && for c in kubectl envsubst; do command -v "$c" >/dev/null 2>&1 || die "'$c' is required for the Karpenter step (or use --no-hooks)."; done
  in_list @build-push "${RUN[@]}" && for c in docker helm kubectl; do command -v "$c" >/dev/null 2>&1 || die "'$c' is required for the image/deploy steps (or use --no-hooks)."; done
else
  in_list @k8s-cleanup "${RUN[@]}" && for c in kubectl helm; do command -v "$c" >/dev/null 2>&1 || die "'$c' is required for the Kubernetes cleanup step."; done
fi

echo "== checking terraform formatting"
terraform fmt -check -recursive "$ROOT/terraform" >/dev/null 2>&1 || die "terraform fmt needed. Run: terraform fmt -recursive terraform"

# ---------------------------------------------------------------- confirmation
echo
echo "${WHITE}${ACTION^^}${NC}  account=$ACCOUNT_ID  region=$AWS_REGION  env=$ENVIRONMENT  state=$TF_STATE_BUCKET"
for i in "${!RUN[@]}"; do printf '  %2d. %s\n' $((i + 1)) "${RUN[$i]}"; done
if [[ "$ACTION" == destroy ]]; then
  echo
  echo "${RED}DESTRUCTIVE ACTION:${NC} deletes every resource of the folders above, including RDS data, S3 objects, DynamoDB items, EFS files,"
  echo "ECR images, logs and KMS keys (pending deletion). 00-bootstrap (the state bucket) is NOT touched."
  (( YES )) || { read -r -p "Type 'destroy' to continue: " a; [[ "$a" == destroy ]] || die "aborted, nothing destroyed."; }
else
  echo
  echo "Applying creates REAL AWS resources that cost money (NAT, EKS, endpoints, ALB, RDS, ...). Run scripts/cost-check.sh afterwards."
  (( YES )) || { read -r -p "Continue? (y/n): " a; [[ "$a" == y ]] || die "aborted, nothing applied."; }
fi

# ---------------------------------------------------------------- helpers
LOGDIR="${TMPDIR:-/tmp}/cloudcart-pipeline-$(date +%Y%m%d-%H%M%S)-$ACTION"; mkdir -p "$LOGDIR"
LOG=""; TAG=""; ABORTED=0
declare -a STATUS=() DONE=() RUNNING=()
for i in "${!RUN[@]}"; do STATUS[$i]=pending; DONE[$i]=""; RUNNING[$i]=""; done
START=$SECONDS

varfile() { local v="$ROOT/envs/$ENVIRONMENT/$1.tfvars"; [[ -f "$v" ]] && echo "-var-file=$v"; return 0; }
tf_apply() { ( cd "$ROOT/terraform/$1" && terraform apply -input=false -no-color tfplan && rm -f tfplan ); }
# shellcheck disable=SC2046
tf_destroy() { ( cd "$ROOT/terraform/$1" && terraform destroy -auto-approve -input=false -no-color $(varfile "$1") ); }
has_state() { aws s3api head-object --bucket "$TF_STATE_BUCKET" --key "$ENVIRONMENT/$1/terraform.tfstate" >/dev/null 2>&1; }

# Deletes what Kubernetes created outside Terraform (load balancers, volumes, Karpenter nodes) so the VPC can be deleted.
k8s_cleanup() {
  if ! aws eks describe-cluster --name "$CLUSTER_NAME" >/dev/null 2>&1; then echo "cluster not found: nothing to clean"; return 0; fi
  aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null || return 1
  helm -n cloudcart uninstall cloudcart 2>/dev/null || true
  kubectl -n cloudcart delete ingress --all --ignore-not-found
  kubectl -n cloudcart delete svc order-service-nlb --ignore-not-found
  kubectl delete -f "$ROOT/kubernetes/storage/ebs-demo.yaml" -f "$ROOT/kubernetes/storage/efs-demo.yaml" --ignore-not-found 2>/dev/null || true
  kubectl -n cloudcart delete pvc --all --ignore-not-found
  kubectl delete nodepools --all --ignore-not-found
  echo "waiting until Karpenter nodes are gone"
  until [[ -z "$(kubectl get nodeclaims -o name 2>/dev/null)" ]]; do echo "  nodeclaims still present"; sleep 10; done
  echo "waiting until the controller-created load balancers are gone"
  until [[ "$(aws elbv2 describe-load-balancers --query "length(LoadBalancers[?contains(LoadBalancerName, 'k8s-cloudcar')])" --output text)" == "0" ]]; do
    echo "  load balancers still deleting"; sleep 10
  done
}

draw() {
  (( TTY )) || return 0
  local n=${#RUN[@]} ok=0 i s info mark color filled width=60
  printf '\033[H\033[2J'
  for s in "${STATUS[@]}"; do [[ "$s" == ok ]] && ok=$((ok + 1)); done
  echo
  echo "  ${CYAN}PIPELINE${NC}  ${ACTION}  |  region ${YELLOW}${AWS_REGION}${NC}  |  env ${YELLOW}${ENVIRONMENT}${NC}  |  $(date +%H:%M:%S)  |  elapsed $((SECONDS - START))s"
  echo
  for i in "${!RUN[@]}"; do
    s="${STATUS[$i]}"; info="${DONE[$i]}${RUNNING[$i]:+${RUNNING[$i]}...}"
    case "$s" in
      running) mark="►"; color="$YELLOW" ;;
      ok) mark="✓"; color="$GREEN" ;;
      failed) mark="✗"; color="$RED" ;;
      *) mark="·"; color="$GRAY" ;;
    esac
    echo "  ${color}${mark} ${RUN[$i]}${NC} ${GRAY}${info:+[$info]}${NC}"
  done
  filled=$((width * ok / n))
  echo
  echo "  ${GREEN}$(printf '%*s' "$filled" '' | tr ' ' '#')${GRAY}$(printf '%*s' $((width - filled)) '' | tr ' ' '.')${NC}  $ok/$n"
}

# stage <index> <label> <command...>: runs one command, appends its output to $LOG, records the time.
stage() {
  local i="$1" label="$2" t=$SECONDS; shift 2
  RUNNING[$i]="$label"; draw
  if "$@" >>"$LOG" 2>&1; then
    DONE[$i]+="$label:$((SECONDS - t))s "; RUNNING[$i]=""; return 0
  fi
  DONE[$i]+="$label:FAILED "; RUNNING[$i]=""; return 1
}

run_item() {
  local i="$1" n="$2" sum a
  case "$n" in
    @k8s-cleanup) stage "$i" cleanup k8s_cleanup ;;
    @karpenter-policy) stage "$i" apply "$ROOT/scripts/deploy-karpenter.sh" ;;
    @build-push)
      stage "$i" build "$ROOT/scripts/build-push.sh" || return 1
      TAG="$(sed -n 's/^Pushed tag: //p' "$LOG" | tail -1)"
      [[ -n "$TAG" ]] || { echo "could not read the pushed tag from the build log" >>"$LOG"; return 1; } ;;
    @deploy-app)
      [[ -n "${TAG:-${IMAGE_TAG:-}}" ]] || { echo "no image tag: set IMAGE_TAG=<tag> or include @build-push in the run" >>"$LOG"; return 1; }
      export IMAGE_TAG="${TAG:-$IMAGE_TAG}"
      stage "$i" deploy "$ROOT/scripts/deploy-app.sh" ;;
    *)
      if [[ "$ACTION" == apply ]]; then
        stage "$i" plan "$ROOT/scripts/tf.sh" "$n" plan || return 1
        sum="$(grep -E 'Plan: [0-9]|No changes' "$LOG" | tail -1 | sed 's/\x1b\[[0-9;]*m//g')"
        DONE[$i]+="(${sum:-no summary}) "
        if (( EACH )); then
          draw; echo; echo "  plan for $n: ${sum:-see $LOG}"
          read -r -p "  apply $n? [y/N] " a </dev/tty
          [[ "$a" == y ]] || { ABORTED=1; return 1; }
        fi
        stage "$i" apply tf_apply "$n" || return 1
        stage "$i" verify "$ROOT/scripts/verify.sh" "$n" || return 1
      else
        if ! has_state "$n"; then DONE[$i]+="skipped:no state "; return 0; fi
        stage "$i" init "$ROOT/scripts/tf.sh" "$n" init || return 1
        stage "$i" destroy tf_destroy "$n" || return 1
      fi ;;
  esac
}

# ---------------------------------------------------------------- run
for i in "${!RUN[@]}"; do
  name="${RUN[$i]}"; STATUS[$i]=running; LOG="$LOGDIR/${name#@}.log"; : >"$LOG"
  draw; (( TTY )) || echo "> $name"
  if run_item "$i" "$name"; then
    STATUS[$i]=ok; (( TTY )) || echo "ok $name ${DONE[$i]}"
  else
    STATUS[$i]=failed; draw
    echo
    if (( ABORTED )); then echo "${YELLOW}stopped by you before applying $name.${NC}"; exit 0; fi
    echo "${RED}FAILED at: $name${NC}   log: $LOG"
    echo "---- last lines ----"; tail -25 "$LOG"; echo "--------------------"
    for k in "${!ORDER[@]}"; do
      if [[ "${ORDER[$k]}" == "$name" ]]; then
        if [[ "$ACTION" == apply ]]; then echo "Fix the cause, then resume:  scripts/pipeline.sh apply $((k + 1))-${#ORDER[@]}"
        else echo "Fix the cause, then resume:  scripts/pipeline.sh destroy 1-$((k + 1))"; fi
      fi
    done
    exit 1
  fi
done

draw
echo
echo "${GREEN}PIPELINE COMPLETED: ${#RUN[@]}/${#RUN[@]} steps, $((SECONDS - START))s.${NC}  logs: $LOGDIR"
if [[ "$ACTION" == apply ]]; then
  echo "Next: scripts/cost-check.sh   |   kubectl -n cloudcart get pods,ingress   |   USER_GUIDE.txt"
else
  echo "00-bootstrap (state bucket) was kept on purpose. Check leftovers that cost money: scripts/cost-check.sh"
fi
