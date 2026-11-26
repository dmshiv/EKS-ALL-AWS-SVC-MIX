#!/usr/bin/env bash
# READ-ONLY report of AWS resources that keep costing money after a lab (run it before you walk away, and after destroy-all.sh).
# Every command only lists. Explanation per check: what it finds and why it matters.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/env.sh" >/dev/null
tag="Project,Values=CloudCart"

section() { echo; echo "== $1"; }

section "EKS clusters (control plane ~\$73/month each)"
aws eks list-clusters --query 'clusters' --output text

section "NAT gateways not deleted (about \$33/month each + data)"
aws ec2 describe-nat-gateways --filter Name=state,Values=available,pending --query 'NatGateways[].[NatGatewayId,VpcId,State]' --output text

section "Load balancers (ALB/NLB ~\$16/month each)"
aws elbv2 describe-load-balancers --query 'LoadBalancers[].[LoadBalancerName,Type,State.Code]' --output text

section "Running EC2 instances (nodes)"
aws ec2 describe-instances --filters Name=instance-state-name,Values=running,pending --query 'Reservations[].Instances[].[InstanceId,InstanceType,Tags[?Key==`Name`]|[0].Value]' --output text

section "Unattached EBS volumes (orphaned PVs keep billing)"
aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].[VolumeId,Size,Tags[?Key==`kubernetes.io/created-for/pvc/name`]|[0].Value]' --output text

section "Elastic IPs (public IPv4 charge even when idle)"
aws ec2 describe-addresses --query 'Addresses[].[PublicIp,AllocationId,AssociationId]' --output text

section "RDS instances / snapshots"
aws rds describe-db-instances --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus]' --output text
aws rds describe-db-snapshots --snapshot-type manual --query 'DBSnapshots[].DBSnapshotIdentifier' --output text

section "ElastiCache replication groups"
aws elasticache describe-replication-groups --query 'ReplicationGroups[].[ReplicationGroupId,Status]' --output text

section "EFS file systems (billed per GB stored until deleted)"
aws efs describe-file-systems --query 'FileSystems[].[FileSystemId,SizeInBytes.Value]' --output text

section "VPC endpoints (interface endpoints ~\$7/month each per AZ)"
aws ec2 describe-vpc-endpoints --query 'VpcEndpoints[?VpcEndpointType==`Interface`].[VpcEndpointId,ServiceName,State]' --output text

section "KMS keys pending deletion / scheduled (\$1/month while they exist)"
aws kms list-aliases --query "Aliases[?contains(AliasName,'cloudcart')].AliasName" --output text

section "CloudWatch log groups (retention!)"
aws logs describe-log-groups --log-group-name-prefix /aws/ --query 'logGroups[?contains(logGroupName,`cloudcart`)].[logGroupName,retentionInDays]' --output text
