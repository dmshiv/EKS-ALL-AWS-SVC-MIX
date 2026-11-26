#!/usr/bin/env bash
# Apply the Karpenter EC2NodeClass + NodePools (kubernetes/karpenter) after terraform/12-karpenter is applied.
#   Terraform (12) = AWS plumbing (IAM, SQS interruption queue, controller).  This script = scheduling POLICY (what nodes may be built).
# Waits (polls) until the CRDs exist and the NodePools report Ready. No sleeps-as-proof: it asks the API.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib.sh"
need kubectl; need envsubst

aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null
export CLUSTER_NAME NODE_ROLE_NAME AMI_ALIAS="${AMI_ALIAS:-al2023@latest}"
NODE_ROLE_NAME="$(state_out 12-karpenter node_role_name)"

echo "== waiting for the Karpenter CRDs (installed by the Helm chart in terraform/12-karpenter)"
until kubectl get crd nodepools.karpenter.sh ec2nodeclasses.karpenter.k8s.aws >/dev/null 2>&1; do echo "  ... CRDs not present yet"; sleep 5; done

for f in ec2nodeclass nodepool-general nodepool-batch-spot; do
  envsubst '${CLUSTER_NAME} ${NODE_ROLE_NAME} ${AMI_ALIAS}' < "$ROOT/kubernetes/karpenter/$f.yaml" | kubectl apply -f -
done

echo "== waiting for the EC2NodeClass to be Ready (it resolves AMI, subnets and security groups by tag)"
until [[ "$(kubectl get ec2nodeclass default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == "True" ]]; do
  echo "  ... EC2NodeClass not Ready yet"; sleep 5
done
kubectl get nodepools,ec2nodeclasses
