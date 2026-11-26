# =============================================================================
# 01-vpc : the network boundary for everything else
# =============================================================================
#
#   Internet
#      |
#   [Internet Gateway]
#      |
#   public subnets   (ALB/NLB, NAT gateway)       10.0.0.0/24 ...      route 0.0.0.0/0 -> IGW
#      |
#   [NAT gateway]
#      |
#   private subnets  (EKS nodes + POD IPs)        10.0.16.0/20 ...     route 0.0.0.0/0 -> NAT
#      |
#   database subnets (RDS, ElastiCache) ISOLATED  10.0.100.0/24 ...    NO default route at all
#
# WHY /20 private subnets? With the AWS VPC CNI every Pod gets a REAL VPC IP address. A /24 (251 usable)
# is exhausted by one busy node pool. /20 = 4091 IPs per AZ leaves room for prefix delegation later.

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # "AZ name" => index, used to carve deterministic CIDRs so a plan never reshuffles subnets.
  az_index = { for i, az in local.azs : az => i }

  cluster_name = local.name # must equal the EKS cluster name created in 06-eks
}

# Only AZs that are enabled for the account (excludes Local Zones / opt-in zones).
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# WHY:    A dedicated VPC instead of the default VPC gives us controlled routing, no surprise public subnets.
# WHAT:   The address space for everything. DNS hostnames + support are REQUIRED: EKS nodes register by
#         private DNS name and interface VPC endpoints resolve through the VPC resolver.
# DEPENDS ON: nothing.  USED BY: all later folders.
# GOES WRONG: overlapping CIDRs break peering/Transit Gateway later; DNS support off breaks endpoints.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

# SECURITY: the default SG allows all traffic between members. Emptying it means anything accidentally
# launched with the default SG is unreachable instead of wide open.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name}-default-DO-NOT-USE" }
}

# WHY:    Gives public subnets a route to the internet (and lets the internet reach public load balancers).
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name}-igw" }
}

# ----------------------------------------------------------------------------- subnets

# PUBLIC: only load balancers and NAT gateways live here. Nodes and pods do NOT.
# TAG kubernetes.io/role/elb=1 is how the AWS Load Balancer Controller discovers where to place
# INTERNET-FACING ALB/NLBs. Without it Ingress stays with "couldn't auto-discover subnets".
resource "aws_subnet" "public" {
  for_each = local.az_index

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.value)
  map_public_ip_on_launch = false # nothing should get a public IP implicitly

  tags = {
    Name                                          = "${local.name}-public-${each.key}"
    Tier                                          = "public"
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

# PRIVATE: EKS worker nodes, Pods (VPC CNI), internal load balancers.
# TAG kubernetes.io/role/internal-elb=1 -> internal ALB/NLB placement.
# TAG karpenter.sh/discovery -> Karpenter's EC2NodeClass finds subnets to launch nodes into.
resource "aws_subnet" "private" {
  for_each = local.az_index

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, each.value + 1)

  tags = {
    Name                                          = "${local.name}-private-${each.key}"
    Tier                                          = "private"
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "karpenter.sh/discovery"                      = local.cluster_name
  }
}

# DATABASE (isolated): RDS and ElastiCache. No route to the internet in either direction.
# They still reach AWS APIs they need (e.g. RDS managed features) through AWS itself, not through us.
resource "aws_subnet" "database" {
  for_each = local.az_index

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 100 + each.value)

  tags = {
    Name = "${local.name}-database-${each.key}"
    Tier = "database"
  }
}

# ----------------------------------------------------------------------------- NAT

locals {
  # LAB: one NAT in the first public subnet. PRODUCTION: one per AZ so an AZ outage does not
  # take down outbound traffic for the other AZs (and avoids cross-AZ data charges).
  nat_azs = var.single_nat_gateway ? [local.azs[0]] : local.azs
}

# EXPENSIVE: an Elastic IP is billed hourly when in use (public IPv4 charge).
resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)

  domain = "vpc"

  tags = { Name = "${local.name}-nat-${each.key}" }

  depends_on = [aws_internet_gateway.this]
}

# WHY:    Private nodes need OUTBOUND internet (pull public images, call APIs without endpoints).
# HOW:    Source-NAT: Pod/node private IP -> NAT public EIP -> IGW -> internet. Inbound connections
#         from the internet cannot be initiated through it.
# COST:   EXPENSIVE. ~$0.045/h per gateway (~$33/month) + $0.045 per GB processed. Gateway/interface
#         VPC endpoints (02-vpc-endpoints) keep AWS-API traffic off the NAT.
# GOES WRONG: if the NAT's AZ dies, private subnets routed to it lose egress (single_nat_gateway=true).
resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = { Name = "${local.name}-nat-${each.key}" }

  depends_on = [aws_internet_gateway.this]
}

# ----------------------------------------------------------------------------- route tables

# WHY:        Public subnets need their own route table whose default route points at the Internet Gateway; private subnets must not share it.
# DEPENDS:    Depends on the VPC; associated with the public subnets; used by the ALB/NLB and NAT gateway.
# GOES WRONG: If a private subnet is accidentally associated with this table its instances become internet-reachable (when they have public IPs).
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name}-public" }
}

# WHY:        The 0.0.0.0/0 route to the IGW is what makes a subnet 'public'.
# DEPENDS:    Depends on the public route table and the Internet Gateway.
# GOES WRONG: Missing route = load balancers and the NAT gateway have no internet path; the ALB never becomes reachable.
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

# WHY:        A subnet uses the VPC main route table until it is explicitly associated; this binds each public subnet to the public table.
# DEPENDS:    Depends on subnets + public route table.
# GOES WRONG: Forgetting an AZ's association silently leaves that AZ on the main table (no internet route).
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# One private route table PER AZ so each AZ can point at its own NAT when single_nat_gateway=false.
resource "aws_route_table" "private" {
  for_each = local.az_index

  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name}-private-${each.key}" }
}

# WHY:        Private nodes and pods need outbound internet (image pulls, STS, public APIs) without being reachable from it: default route to NAT.
# DEPENDS:    Depends on the private route table(s) and the NAT gateway(s). LAB: single NAT. PRODUCTION: one NAT per AZ.
# GOES WRONG: NAT in a failed AZ breaks outbound traffic for every private subnet that routes through it; NAT data processing is a top bill item.
resource "aws_route" "private_nat" {
  for_each = local.az_index

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? local.azs[0] : each.key].id
}

# WHY:        Binds each private subnet to the route table that sends 0.0.0.0/0 to NAT.
# DEPENDS:    Depends on private subnets + private route tables.
# GOES WRONG: A missing association means nodes cannot reach the internet or the EKS endpoint and fail to join the cluster.
resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# Database route table has ONLY the implicit local route (VPC CIDR). That is the isolation:
# there is simply no path to the internet, even if a security group were mis-configured.
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name}-database" }
}

# WHY:        Database subnets get a route table WITHOUT a default route: databases are reachable only from inside the VPC.
# DEPENDS:    Depends on database subnets; used by RDS and ElastiCache subnet groups.
# GOES WRONG: Adding a default route here later silently breaks the isolation guarantee the security design relies on.
resource "aws_route_table_association" "database" {
  for_each = aws_subnet.database

  subnet_id      = each.value.id
  route_table_id = aws_route_table.database.id
}

# NACLs: the default (allow-all) NACL is kept on purpose. Security Groups are stateful and
# per-ENI, so they are the primary control; custom NACLs are stateless and easy to get wrong.
# PRODUCTION: add NACLs on the database tier if your compliance regime demands defence in depth.
