#!/usr/bin/env bash
# Post-apply verification of REAL AWS resources, one function per folder. Read-only (describe/list/get calls only).
#   scripts/verify.sh 01-vpc
#
# NO ARTIFICIAL SLEEPS AS PROOF OF READINESS: asynchronous resources are POLLED until they report the target state.
# The loop only ends on (a) target reached, or (b) a terminal failure state. There is no fixed timeout: AWS may take a while,
# and a failed resource is reported as failed, not as "timed out". Press Ctrl+C to stop waiting.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/env.sh" >/dev/null
folder="${1:?usage: verify.sh <folder>}"; folder="${folder%/}"
NAME="${PROJECT}-${ENVIRONMENT}"

pass() { echo "  PASS  $*"; }
fail() { echo "  FAIL  $*" >&2; exit 1; }
step() { echo; echo "== $*"; }

# wait_for "<description>" "<command printing the current state>" "<target regex>" "<failure regex>"
wait_for() {
  local desc="$1" cmd="$2" ok="$3" bad="$4" state
  while true; do
    state="$(eval "$cmd" 2>/dev/null || echo UNKNOWN)"
    if [[ "$state" =~ $ok ]]; then pass "$desc -> $state"; return 0; fi
    if [[ -n "$bad" && "$state" =~ $bad ]]; then fail "$desc reached terminal failure state: $state"; fi
    echo "  ...   $desc is '$state', waiting"; sleep 10
  done
}

tf_out() { (cd "$ROOT/terraform/$1" && terraform output -raw "$2"); }
tf_json() { (cd "$ROOT/terraform/$1" && terraform output -json "$2"); }

verify_00_bootstrap() {
  local b="$TF_STATE_BUCKET"
  step "state bucket exists  [aws s3api head-bucket: succeeds only if the bucket exists AND you may access it]"
  aws s3api head-bucket --bucket "$b" && pass "bucket $b"
  step "versioning enabled  [get-bucket-versioning: expect Status=Enabled]"
  [[ "$(aws s3api get-bucket-versioning --bucket "$b" --query Status --output text)" == Enabled ]] && pass "versioning" || fail "versioning not Enabled"
  step "default encryption  [get-bucket-encryption: expect AES256 or aws:kms]"
  aws s3api get-bucket-encryption --bucket "$b" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text | grep -Eq 'AES256|aws:kms' && pass "encryption" || fail "no encryption"
  step "public access fully blocked  [get-public-access-block: all four flags must be true]"
  [[ "$(aws s3api get-public-access-block --bucket "$b" --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,BlockPublicPolicy,IgnorePublicAcls,RestrictPublicBuckets]' --output text | tr -s '\t' ' ')" == "True True True True" ]] && pass "public access blocked" || fail "public access not fully blocked"
}

verify_01_vpc() {
  local vpc; vpc="$(tf_out 01-vpc vpc_id)"
  step "VPC available with DNS enabled  [describe-vpcs; DNS attrs via describe-vpc-attribute]"
  wait_for "VPC $vpc" "aws ec2 describe-vpcs --vpc-ids $vpc --query 'Vpcs[0].State' --output text" '^available$' 'XXX'
  for attr in enableDnsSupport enableDnsHostnames; do
    [[ "$(aws ec2 describe-vpc-attribute --vpc-id "$vpc" --attribute "$attr" --query "${attr^}.Value" --output text)" == True ]] && pass "$attr" || fail "$attr is false"
  done
  step "subnets per tier  [describe-subnets filtered by Tier tag: expect az_count of each]"
  for tier in public private database; do
    n="$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" "Name=tag:Tier,Values=$tier" --query 'length(Subnets)' --output text)"
    [[ "$n" -ge 2 ]] && pass "$tier subnets: $n" || fail "$tier subnets: $n (need >=2)"
  done
  step "EKS discovery tags on subnets  [elb on public, internal-elb + karpenter discovery on private]"
  [[ "$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" "Name=tag:kubernetes.io/role/elb,Values=1" --query 'length(Subnets)' --output text)" -ge 2 ]] && pass "role/elb" || fail "public subnets lack kubernetes.io/role/elb"
  [[ "$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" "Name=tag:kubernetes.io/role/internal-elb,Values=1" "Name=tag:karpenter.sh/discovery,Values=$NAME" --query 'length(Subnets)' --output text)" -ge 2 ]] && pass "internal-elb + karpenter discovery" || fail "private subnet tags missing"
  step "NAT gateway(s) available  [describe-nat-gateways: state must become 'available'; 'failed' is terminal]"
  for nat in $(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc" "Name=state,Values=pending,available" --query 'NatGateways[].NatGatewayId' --output text); do
    wait_for "NAT $nat" "aws ec2 describe-nat-gateways --nat-gateway-ids $nat --query 'NatGateways[0].State' --output text" '^available$' '^(failed|deleted|deleting)$'
  done
  step "database route table has NO default route  [isolation proof: expect 0 routes to 0.0.0.0/0]"
  rt="$(tf_out 01-vpc database_route_table_id)"
  n="$(aws ec2 describe-route-tables --route-table-ids "$rt" --query "length(RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'])" --output text)"
  [[ "$n" == 0 ]] && pass "database subnets are isolated" || fail "database route table has a default route!"
  step "private route tables send 0.0.0.0/0 to a NAT gateway"
  for rt in $(tf_json 01-vpc private_route_table_ids | jq -r '.[]'); do
    t="$(aws ec2 describe-route-tables --route-table-ids "$rt" --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].NatGatewayId | [0]" --output text)"
    [[ "$t" == nat-* ]] && pass "$rt -> $t" || fail "$rt has no NAT default route"
  done
}

verify_02_vpc_endpoints() {
  local vpc; vpc="$(tf_out 01-vpc vpc_id)"
  step "gateway endpoints present  [describe-vpc-endpoints: S3 + DynamoDB, state available]"
  for svc in s3 dynamodb; do
    id="$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpc" "Name=service-name,Values=com.amazonaws.$AWS_REGION.$svc" --query 'VpcEndpoints[0].VpcEndpointId' --output text)"
    [[ "$id" == vpce-* ]] || fail "no $svc gateway endpoint"
    wait_for "$svc endpoint $id" "aws ec2 describe-vpc-endpoints --vpc-endpoint-ids $id --query 'VpcEndpoints[0].State' --output text" '^[Aa]vailable$' '^([Ff]ailed|[Rr]ejected|[Dd]eleted)$'
  done
  step "interface endpoints available with private DNS  [PrivateLink: state must be 'available']"
  ids="$(tf_json 02-vpc-endpoints interface_endpoint_ids | jq -r 'to_entries[] | "\(.key)=\(.value)"')"
  [[ -z "$ids" ]] && echo "  (interface endpoints disabled by variable)"
  for kv in $ids; do
    svc="${kv%%=*}"; id="${kv##*=}"
    wait_for "$svc endpoint $id" "aws ec2 describe-vpc-endpoints --vpc-endpoint-ids $id --query 'VpcEndpoints[0].State' --output text" '^[Aa]vailable$' '^([Ff]ailed|[Rr]ejected|[Dd]eleted)$'
    [[ "$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids "$id" --query 'VpcEndpoints[0].PrivateDnsEnabled' --output text)" == True ]] && pass "$svc private DNS" || fail "$svc private DNS disabled"
  done
}

verify_03_security_groups() {
  step "four security groups exist  [describe-security-groups by name tag]"
  for n in nodes rds redis efs; do
    id="$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=${NAME}-${n}" --query 'SecurityGroups[0].GroupId' --output text)"
    [[ "$id" == sg-* ]] && pass "$n -> $id" || fail "security group ${NAME}-${n} missing"
  done
}

verify_16_kms() {
  step "keys enabled with rotation  [describe-key + get-key-rotation-status]"
  for a in data eks-secrets; do
    [[ "$(aws kms describe-key --key-id "alias/${NAME}-${a}" --query KeyMetadata.KeyState --output text)" == Enabled ]] && pass "alias/${NAME}-${a} Enabled" || fail "key $a not Enabled"
    [[ "$(aws kms get-key-rotation-status --key-id "alias/${NAME}-${a}" --query KeyRotationEnabled --output text)" == True ]] && pass "rotation on" || fail "rotation off"
  done
}

verify_04_ecr() {
  step "four repositories with IMMUTABLE tags and scan on push  [describe-repositories]"
  n="$(aws ecr describe-repositories --query "length(repositories[?starts_with(repositoryName,'cloudcart-') && imageTagMutability=='IMMUTABLE' && imageScanningConfiguration.scanOnPush==\`true\`])" --output text)"
  [[ "$n" -ge 4 ]] && pass "$n repositories OK" || fail "expected 4 immutable+scanned repositories, found $n"
}

verify_06_eks() {
  step "cluster ACTIVE (polled; creation takes 10-15 minutes)  [aws eks describe-cluster]"
  wait_for "cluster $NAME" "aws eks describe-cluster --name $NAME --query cluster.status --output text" '^ACTIVE$' '^(FAILED|DELETING)$'
  step "authentication mode API and add-ons"
  [[ "$(aws eks describe-cluster --name "$NAME" --query cluster.accessConfig.authenticationMode --output text)" == API ]] && pass "authentication_mode API" || fail "not API mode"
  for a in vpc-cni kube-proxy eks-pod-identity-agent; do
    wait_for "add-on $a" "aws eks describe-addon --cluster-name $NAME --addon-name $a --query addon.status --output text" '^ACTIVE$' '^(CREATE_FAILED|DEGRADED)$'
  done
}

verify_10_node_groups() {
  step "node group ACTIVE then nodes Ready  [aws eks describe-nodegroup + kubectl]"
  wait_for "node group system" "aws eks describe-nodegroup --cluster-name $NAME --nodegroup-name system --query nodegroup.status --output text" '^ACTIVE$' '^(CREATE_FAILED|DEGRADED)$'
  aws eks update-kubeconfig --name "$NAME" --region "$AWS_REGION" >/dev/null
  wait_for "all nodes Ready" "kubectl get nodes --no-headers | awk '{print \$2}' | sort -u | tr '\n' ' '" '^Ready $' 'XXX'
  wait_for "coredns add-on" "aws eks describe-addon --cluster-name $NAME --addon-name coredns --query addon.status --output text" '^ACTIVE$' '^(CREATE_FAILED|DEGRADED)$'
}

verify_19_rds() {
  step "RDS available, encrypted, private  [describe-db-instances; polled]"
  wait_for "RDS ${NAME}-orders" "aws rds describe-db-instances --db-instance-identifier ${NAME}-orders --query 'DBInstances[0].DBInstanceStatus' --output text" '^available$' '^(failed|incompatible.*|deleting)$'
  [[ "$(aws rds describe-db-instances --db-instance-identifier "${NAME}-orders" --query 'DBInstances[0].[StorageEncrypted,PubliclyAccessible]' --output text | tr -s '\t' ' ')" == "True False" ]] && pass "encrypted, not public" || fail "RDS must be encrypted and private"
}

verify_21_elasticache() {
  step "replication group available  [describe-replication-groups; polled]"
  wait_for "cache ${NAME}-cache" "aws elasticache describe-replication-groups --replication-group-id ${NAME}-cache --query 'ReplicationGroups[0].Status' --output text" '^available$' '^(create-failed|deleting)$'
}

verify_27_acm() {
  step "certificate ISSUED (polled; DNS validation)  [aws acm list-certificates]"
  arn="$(tf_out 27-acm alb_certificate_arn)"
  [[ -z "$arn" ]] && { echo "  (DNS disabled: no certificate)"; return 0; }
  wait_for "certificate" "aws acm describe-certificate --certificate-arn $arn --query Certificate.Status --output text" '^ISSUED$' '^(FAILED|VALIDATION_TIMED_OUT)$'
}

verify_12_karpenter() {
  step "Karpenter controller available  [kubectl rollout status]"
  aws eks update-kubeconfig --name "$NAME" --region "$AWS_REGION" >/dev/null
  kubectl -n kube-system rollout status deploy/karpenter --timeout=0 >/dev/null 2>&1 || wait_for "karpenter" "kubectl -n kube-system get deploy karpenter -o jsonpath='{.status.availableReplicas}'" '^[1-9]' 'XXX'
  pass "karpenter available"
}

verify_28_load_balancer_controller() {
  step "AWS Load Balancer Controller available"
  aws eks update-kubeconfig --name "$NAME" --region "$AWS_REGION" >/dev/null
  wait_for "aws-load-balancer-controller" "kubectl -n kube-system get deploy aws-load-balancer-controller -o jsonpath='{.status.availableReplicas}'" '^[1-9]' 'XXX'
}

fn="verify_$(echo "$folder" | tr '-' '_')"
if declare -F "$fn" >/dev/null; then
  "$fn"; echo; echo "VERIFIED: $folder"
else
  echo "No automated verifier for $folder yet (added in its phase)."
fi
