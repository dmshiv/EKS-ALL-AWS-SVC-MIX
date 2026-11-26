#!/usr/bin/env bash
# Render the kubernetes/ templates (envsubst) into .rendered/ using values read from Terraform state. NOTHING is applied to a cluster.
#   scripts/render-k8s.sh && kubectl apply -f .rendered/<dir>/
# Why envsubst and not Helm for these? They are small standalone lab manifests; the application itself is deployed with Helm (deploy-app.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib.sh"
need envsubst; need jq; need aws

export AWS_REGION
export CLUSTER_NAME
export SSM_PREFIX="$(state_out 18-parameter-store ssm_prefix)"
export VPC_CIDR="$(state_out 01-vpc vpc_cidr)"
export KMS_KEY_ARN="$(state_out 16-kms data_key_arn)"
export EFS_ID="$(state_out_opt 14-efs efs_file_system_id)"
export EFS_AP_ID="$(state_out_opt 14-efs efs_access_point_id)"
export POD_SG_ID="$(state_out_opt 43-security-groups-for-pods pods_db_security_group_id)"
export IRSA_DEMO_ROLE_ARN="$(state_out_opt 09-irsa irsa_demo_role_arn)"
export NODE_ROLE_NAME="$(state_out_opt 12-karpenter node_role_name)"
export AMI_ALIAS="${AMI_ALIAS:-al2023@latest}"   # PRODUCTION: pin a version, e.g. al2023@v20250101
export CERT_ARN="$(state_out_opt 27-acm alb_certificate_arn)"
export WAF_ARN="$(state_out_opt 33-waf web_acl_arn)"
export LOGS_BUCKET="$(state_out_opt 29-alb access_logs_bucket)"
export ORIGIN_HOST="$(state_out_opt 26-route53 origin_fqdn)"
export NLB_EIPS="$(state_out_opt 30-nlb eip_allocation_ids)"
export NLB_SUBNETS="$(state_out_opt 30-nlb public_subnet_ids | jq -r 'if .=="" then "" else join(",") end' 2>/dev/null || true)"
export ORDERS_QUEUE_URL="$(state_out_opt 22-sqs orders_queue_url)"
export IMAGE_REGISTRY="$(state_out_opt 04-ecr registry_url)"
export IMAGE_TAG="${IMAGE_TAG:-v1.0.0}"

VARS='${AWS_REGION} ${CLUSTER_NAME} ${SSM_PREFIX} ${VPC_CIDR} ${KMS_KEY_ARN} ${EFS_ID} ${EFS_AP_ID} ${POD_SG_ID} ${IRSA_DEMO_ROLE_ARN} ${NODE_ROLE_NAME} ${AMI_ALIAS} ${CERT_ARN} ${WAF_ARN} ${LOGS_BUCKET} ${ORIGIN_HOST} ${NLB_EIPS} ${NLB_SUBNETS} ${ORDERS_QUEUE_URL} ${IMAGE_REGISTRY} ${IMAGE_TAG}'

OUT="$ROOT/.rendered"
rm -rf "$OUT"; mkdir -p "$OUT"
while IFS= read -r -d '' f; do
  rel="${f#"$ROOT"/kubernetes/}"
  mkdir -p "$OUT/$(dirname "$rel")"
  envsubst "$VARS" < "$f" > "$OUT/$rel"
done < <(find "$ROOT/kubernetes" -name '*.yaml' -print0)

if [[ -z "$ORIGIN_HOST" || -z "$CERT_ARN" ]]; then
  rm -f "$OUT/ingress/ingress.yaml"
  echo "NOTE: no domain/certificate in state -> ingress/ingress.yaml skipped. Deploy with Helm (scripts/deploy-app.sh): its Ingress works over HTTP without a domain."
fi
echo "rendered to $OUT (not applied)."
