# =============================================================================
# 03-security-groups : firewalls created BEFORE the cluster
# =============================================================================
#
#  Pod --(VPC CNI gives the pod an IP on a node ENI)--> the node ENI carries node-sg (+ the EKS cluster SG)
#   |
#   +--> RDS    sg: tcp/5432 FROM node-sg
#   +--> Redis  sg: tcp/6379 FROM node-sg
#   +--> EFS    sg: tcp/2049 FROM node-sg
#
# WHY node-sg EXISTS (instead of using the EKS-created "cluster primary SG" as the rule source):
#   The cluster SG only exists after 06-eks, but these rules are needed by folders that must not wait for it.
#   Creating our own node security group first lets the data tier reference a stable source SG, and the node group (10)
#   and Karpenter nodes (12) simply attach it. Data-tier rules never change when the cluster is rebuilt.
#
# SG REFERENCES, NOT CIDRs: "source = sg-xxxx" follows instances automatically, survives IP churn (pods and nodes change IPs
#   constantly) and cannot be satisfied by an unrelated host in the same subnet.
#
# SECURITY GROUP vs NETWORKPOLICY vs IAM (see docs/security): SGs filter at the ENI/VPC level using IPs/SGs; NetworkPolicy filters
#   pod-to-pod inside the cluster using labels; IAM controls AWS API permissions. They stack; none replaces another.
#
# COST: security groups are free.

# ----------------------------------------------------------------------------- node SG
# WHY:    Attached (with the EKS cluster SG) to every worker node ENI. Pods share the node's ENI, so "from node-sg" means
#         "from any pod running on those nodes" (use Security Groups for Pods, folder 43, to narrow it to specific pods).
# WHAT:   Self-referencing ingress (node <-> node: CoreDNS, pod traffic) and open egress.
# DEPENDS ON: VPC.  USED BY: 10-node-groups launch template, 12-karpenter EC2NodeClass (found by the discovery tag).
# GOES WRONG: removing the egress rule blocks image pulls, STS, ECR... nodes go NotReady. A SECOND SG with tag
#         kubernetes.io/cluster/<name> on the same ENI breaks the AWS Load Balancer Controller, so we do NOT add that tag here.
resource "aws_security_group" "nodes" {
  name_prefix = "${local.name}-nodes-"
  description = "CloudCart EKS worker nodes (source SG for data-tier rules)"
  vpc_id      = local.vpc_id

  tags = {
    Name                     = "${local.name}-nodes"
    "karpenter.sh/discovery" = local.name
  }

  lifecycle {
    create_before_destroy = true
  }
}

# WHY:        Nodes and pods must talk to each other (kubelet, CoreDNS, pod to pod across nodes).
# DEPENDS:    Depends on the node SG; used by every node group, Karpenter nodes and the cluster.
# GOES WRONG: Without self-referencing ingress cross-node pod traffic and DNS time out while same-node traffic still works (confusing partial failure).
resource "aws_vpc_security_group_ingress_rule" "nodes_self" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "node-to-node and pod-to-pod traffic"
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"
}

# WHY:        Nodes need outbound access to the control plane, ECR, STS and the internet via NAT; SGs are stateful so replies are allowed.
# DEPENDS:    Depends on the node SG.
# GOES WRONG: Restricting egress too far breaks image pulls and AWS API calls with timeouts, not errors.
resource "aws_vpc_security_group_egress_rule" "nodes_all" {
  security_group_id = aws_security_group.nodes.id
  description       = "outbound: ECR, STS, DNS, AWS APIs, databases"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ----------------------------------------------------------------------------- RDS
# WHY:    Only workloads on EKS nodes may open PostgreSQL connections.
# WHAT DEPENDS ON IT: 19-rds. GOES WRONG: missing rule => pod gets "connection timed out" (not "refused": an SG DROPS silently).
resource "aws_security_group" "rds" {
  name_prefix = "${local.name}-rds-"
  description = "PostgreSQL from EKS nodes"
  vpc_id      = local.vpc_id

  tags = { Name = "${local.name}-rds" }

  lifecycle {
    create_before_destroy = true
  }
}

# WHY:        The database accepts connections ONLY from the node security group (SG-to-SG), not from CIDRs.
# DEPENDS:    Depends on the RDS SG and node SG; used by 19-rds.
# GOES WRONG: Pod to RDS timeouts almost always mean this rule is missing or the pod uses a different SG (see 43 Security Groups for Pods).
resource "aws_vpc_security_group_ingress_rule" "rds_from_nodes" {
  security_group_id            = aws_security_group.rds.id
  description                  = "Postgres from nodes/pods"
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "tcp"
  from_port                    = local.postgres_port
  to_port                      = local.postgres_port
}

# ----------------------------------------------------------------------------- Redis
resource "aws_security_group" "redis" {
  name_prefix = "${local.name}-redis-"
  description = "Redis/Valkey from EKS nodes"
  vpc_id      = local.vpc_id

  tags = { Name = "${local.name}-redis" }

  lifecycle {
    create_before_destroy = true
  }
}

# WHY:        Redis accepts 6379 only from nodes.
# DEPENDS:    Depends on the Redis SG and node SG; used by 21-elasticache.
# GOES WRONG: Connection timeout from the order service while TLS/auth are correct = this rule.
resource "aws_vpc_security_group_ingress_rule" "redis_from_nodes" {
  security_group_id            = aws_security_group.redis.id
  description                  = "Redis from nodes/pods"
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "tcp"
  from_port                    = local.redis_port
  to_port                      = local.redis_port
}

# ----------------------------------------------------------------------------- EFS
# NFS is mounted by the NODE (kernel NFS client / efs-utils), not by the pod process, so the source is the node SG.
# Missing rule => pod stuck ContainerCreating with "mount.nfs: Connection timed out".
resource "aws_security_group" "efs" {
  name_prefix = "${local.name}-efs-"
  description = "NFS from EKS nodes"
  vpc_id      = local.vpc_id

  tags = { Name = "${local.name}-efs" }

  lifecycle {
    create_before_destroy = true
  }
}

# WHY:        NFS (2049) must be open from nodes to the EFS mount targets.
# DEPENDS:    Depends on the EFS SG and node SG; used by 14-efs mount targets.
# GOES WRONG: Pods stuck ContainerCreating with 'mount.nfs: Connection timed out' = this rule or a missing mount target in the pod's AZ.
resource "aws_vpc_security_group_ingress_rule" "efs_from_nodes" {
  security_group_id            = aws_security_group.efs.id
  description                  = "NFS from nodes"
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "tcp"
  from_port                    = local.nfs_port
  to_port                      = local.nfs_port
}
