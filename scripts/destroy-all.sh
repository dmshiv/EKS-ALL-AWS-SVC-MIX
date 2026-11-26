#!/usr/bin/env bash
# Guided teardown in REVERSE dependency order. It NEVER destroys anything without an explicit typed confirmation per step.
#   scripts/destroy-all.sh
#
# WHY NOT JUST `terraform destroy` EVERYWHERE?  Resources created OUTSIDE Terraform keep AWS bills running and BLOCK deletion:
#   - an Ingress/Service-type-LoadBalancer creates an ALB/NLB (+ target groups + security groups) through the controller
#   - PVCs create EBS volumes and EFS access points
#   - Karpenter creates EC2 instances and launch templates
#   - ExternalDNS creates Route 53 records
# Terraform does not know them, so the VPC cannot be deleted ("DependencyViolation") and the instances/volumes/ALBs keep billing.
# So step 0 deletes the Kubernetes objects that own those AWS resources and WAITS for the AWS side to disappear.
#
# DESTRUCTIVE ACTIONS (read before typing "yes"):
#   RDS data (final snapshot only if skip_final_snapshot=false), S3 objects (force_destroy=true in the lab), DynamoDB items, EFS files,
#   ECR images (force_delete=true), CloudWatch logs, KMS keys (7-30 day deletion window), Secrets (recovery window).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

confirm() { read -r -p "$1 Type 'yes' to continue: " a; [[ "$a" == yes ]] || { echo "aborted."; exit 1; }; }

confirm "STEP 0: delete Helm release 'cloudcart', ingress/NLB services, demo PVCs, Karpenter NodePools in cluster $CLUSTER_NAME."
if aws eks describe-cluster --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null
  helm -n cloudcart uninstall cloudcart 2>/dev/null || true
  kubectl -n cloudcart delete ingress --all --ignore-not-found
  kubectl -n cloudcart delete svc order-service-nlb --ignore-not-found
  kubectl delete -f "$ROOT/kubernetes/storage/ebs-demo.yaml" -f "$ROOT/kubernetes/storage/efs-demo.yaml" --ignore-not-found 2>/dev/null || true
  kubectl -n cloudcart delete pvc --all --ignore-not-found
  kubectl delete nodepools --all --ignore-not-found     # Karpenter drains and terminates its instances
  echo "== waiting until Karpenter nodes are gone"
  until [[ -z "$(kubectl get nodeclaims -o name 2>/dev/null)" ]]; do echo "  ... nodeclaims still present"; sleep 10; done
  echo "== waiting until the load balancers created by the controller are gone"
  until [[ "$(aws elbv2 describe-load-balancers --query "length(LoadBalancers[?contains(LoadBalancerName, 'k8s-cloudcar')])" --output text)" == "0" ]]; do
    echo "  ... load balancers still deleting"; sleep 10
  done
else
  echo "cluster not found: nothing to clean inside Kubernetes."
fi

# Reverse of scripts/execution-order.txt, excluding comment lines and the bootstrap bucket (kept until you decide).
mapfile -t ORDER < <(grep -vE '^(#|$)' "$ROOT/scripts/execution-order.txt")
for ((i=${#ORDER[@]}-1; i>=0; i--)); do
  f="${ORDER[$i]}"
  [[ "$f" == 00-bootstrap ]] && continue
  if aws s3api head-object --bucket "$TF_STATE_BUCKET" --key "$ENVIRONMENT/$f/terraform.tfstate" >/dev/null 2>&1; then
    echo; echo "### $f"
    "$ROOT/scripts/tf.sh" "$f" destroy      # prints DESTRUCTIVE banner and asks for 'destroy <folder>'
  else
    echo "### $f: no state, skipping"
  fi
done

echo
echo "Everything except 00-bootstrap is destroyed. The state bucket holds the history of every folder."
echo "Remove it last and deliberately (prevent_destroy must be removed first): see terraform/00-bootstrap/README.md"
echo "CHECK for leftovers that cost money:  scripts/cost-check.sh"
