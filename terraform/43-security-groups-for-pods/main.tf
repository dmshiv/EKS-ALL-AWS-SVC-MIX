# =============================================================================
# 43-security-groups-for-pods : give SPECIFIC pods their own security group
# =============================================================================
#
# PROBLEM: normally all pods on a node share the node ENI's security groups, so "RDS allows node-sg" means ANY pod on those nodes can reach
# the database (including a compromised frontend). Security Groups for Pods (SGP) gives a pod its own BRANCH ENI with its own SG.
#
#   Pod (selected by SecurityGroupPolicy) --> branch ENI [pods-db SG] --> RDS SG: allow 5432 FROM pods-db SG   (only these pods)
#   other pods on the same node                --> node ENI [node-sg]       --> RDS SG: blocked IF you remove the node-sg rule (03) -- the exercise
#
# HOW IT WORKS: the VPC CNI (ENABLE_POD_ENI=true, set by 06-eks var vpc_cni_pod_eni) asks the VPC Resource Controller (cluster role has
# AmazonEKSVPCResourceController, 05-iam) to attach a TRUNK ENI to a supported node; each selected pod gets a BRANCH ENI off the trunk.
# The pod is selected by a SecurityGroupPolicy custom resource (kubernetes/security-groups-for-pods/securitygrouppolicy.yaml) that maps a
# pod label/ServiceAccount to security group IDs (this folder's output).
# LIMITS: needs Nitro instances that support trunking (m5/c5/r5... NOT t3, so run the demo pods on Karpenter nodes); fewer pods per node
# (branch ENI quota); pods need the cluster SG rule below for DNS/probes; NetworkPolicy still applies on top.
# WHEN TO USE: compliance requirements for per-workload DB access, or when NetworkPolicy alone is not accepted by auditors. Otherwise prefer
# NetworkPolicy + IAM (simpler, no instance restrictions).
# COST: none (ENIs are free), but fewer pods per node = more nodes.
# DEPENDS ON: 01-vpc, 03-security-groups (rds SG), 06-eks (cluster SG). GOES WRONG: pod stuck ContainerCreating "failed to assign branch ENI":
# unsupported instance type or trunking not enabled; DNS fails: missing cluster-SG ingress rule for the pod SG.

# WHY:        Gives selected pods their own security group so only THOSE pods (not every pod on the node) may reach the database.
# DEPENDS:    Depends on 01-vpc; referenced by the SecurityGroupPolicy in kubernetes/security-groups-for-pods.
# GOES WRONG: Needs ENABLE_POD_ENI on the CNI and supported instance types; pods stay ContainerCreating if branch ENIs are unavailable.
resource "aws_security_group" "pods_db" {
  name_prefix = "${local.name}-pods-db-"
  description = "Pods allowed to reach the database (Security Groups for Pods)"
  vpc_id      = local.vpc_id

  tags = { Name = "${local.name}-pods-db" }

  lifecycle {
    create_before_destroy = true
  }
}

# WHY:        Pods in this SG still need outbound access to DNS, the database and AWS APIs.
# DEPENDS:    Depends on the pod SG.
# GOES WRONG: Too-tight egress breaks DNS (UDP/TCP 53) and shows up as random timeouts.
resource "aws_vpc_security_group_egress_rule" "pods_db_all" {
  security_group_id = aws_security_group.pods_db.id
  description       = "pods may initiate outbound traffic (DB, DNS, AWS APIs)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# kubelet probes and node-originated traffic must reach the pod.
resource "aws_vpc_security_group_ingress_rule" "pods_db_from_cluster" {
  security_group_id            = aws_security_group.pods_db.id
  description                  = "kubelet probes and node traffic"
  referenced_security_group_id = local.cluster_sg_id
  ip_protocol                  = "-1"
}

# CoreDNS runs with the cluster SG; a pod on a branch ENI must be allowed to reach it on 53 or DNS silently fails.
resource "aws_vpc_security_group_ingress_rule" "cluster_from_pods_db" {
  security_group_id            = local.cluster_sg_id
  description                  = "pods with dedicated SG may reach CoreDNS/nodes"
  referenced_security_group_id = aws_security_group.pods_db.id
  ip_protocol                  = "-1"
}

# THE POINT: the database accepts these pods explicitly.
resource "aws_vpc_security_group_ingress_rule" "rds_from_pods_db" {
  security_group_id            = local.rds_sg_id
  description                  = "Postgres from pods that use the dedicated pod SG"
  referenced_security_group_id = aws_security_group.pods_db.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
