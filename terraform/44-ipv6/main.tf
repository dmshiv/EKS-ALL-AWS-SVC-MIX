# =============================================================================
# 44-ipv6 : IPv6 and EKS (design + a free dual-stack lab VPC)
# =============================================================================
#
# EKS IPv6 FACTS (verify against current AWS docs before a production decision)
#   - Chosen AT CLUSTER CREATION: kubernetes_network_config.ip_family = "ipv6" (06-eks variable ip_family). It cannot be changed afterwards.
#   - Pods and Services get IPv6 addresses only (no IPv4 pod IPs). Pods reach IPv4-only endpoints through DNS64/NAT64 (needs a NAT gateway
#     with DNS64 on the subnet) or the node's IPv4 for host-network traffic. The node itself stays dual-stack.
#   - IP EXHAUSTION DISAPPEARS: a /64 subnet has 2^64 addresses, so no prefix delegation, no secondary CIDR tricks, no "subnet out of IPs".
#   - Egress to the internet uses an EGRESS-ONLY Internet Gateway (stateful, outbound only): NO NAT GATEWAY COST for IPv6 traffic.
#   - Requirements: dual-stack VPC and subnets, Nitro instances, VPC CNI IPv6 mode, and AWS Load Balancer Controller target-type ip with
#     ip-address-type dualstack. Many third-party tools and some AWS endpoints (check each service) still need IPv4 paths.
#   - Why not default: operational unfamiliarity, IPv4-only dependencies (some SaaS, on-prem), security tooling gaps, and extra DNS64 design.
#
# WHAT THIS FOLDER BUILDS (optional, free): a separate small dual-stack VPC so you can SEE IPv6 addressing and routing:
#
#   Internet <--IGW--> public subnet  (IPv4 /24 + IPv6 /64)  routes: 0.0.0.0/0 and ::/0 -> IGW
#   Internet <--EIGW-- private subnet (IPv4 /24 + IPv6 /64)  routes: ::/0 -> egress-only IGW   (outbound IPv6 only, nothing inbound)
#
# PACKET FLOW (IPv6, private subnet): instance -> ::/0 route -> egress-only IGW -> internet; replies return on the same flow; unsolicited inbound
# is impossible (that is the "private" property, delivered without NAT).
# COST: $0 (VPC, subnets, IGW, egress-only IGW are free; no NAT, no instances). IPv4 public addresses/EIPs are NOT created here.

# WHY:        Separate small VPC for the IPv6 experiment so the main VPC stays IPv4 and unchanged.
# DEPENDS:    Used by nothing else; created only when enabled.
# GOES WRONG: EKS IPv6 clusters cannot be converted from IPv4: this is an experiment VPC, not a migration.
resource "aws_vpc" "lab" {
  count = var.enable_ipv6_lab ? 1 : 0

  cidr_block                       = var.lab_vpc_cidr
  assign_generated_ipv6_cidr_block = true
  enable_dns_support               = true
  enable_dns_hostnames             = true

  tags = { Name = "${local.name}-ipv6-lab" }
}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# WHY:        Provides the public IPv6 route for the public subnets.
# DEPENDS:    Depends on the lab VPC.
# GOES WRONG: Missing IGW means no IPv6 egress for public subnets.
resource "aws_internet_gateway" "lab" {
  count = var.enable_ipv6_lab ? 1 : 0

  vpc_id = aws_vpc.lab[0].id

  tags = { Name = "${local.name}-ipv6-lab-igw" }
}

# Egress-only IGW: the IPv6 equivalent of "private subnet with NAT", without the NAT.
resource "aws_egress_only_internet_gateway" "lab" {
  count = var.enable_ipv6_lab ? 1 : 0

  vpc_id = aws_vpc.lab[0].id

  tags = { Name = "${local.name}-ipv6-lab-eigw" }
}

# WHY:        Dual-stack public subnets (IPv4 + IPv6 /64) in each AZ.
# DEPENDS:    Depends on the lab VPC and its IPv6 CIDR.
# GOES WRONG: Wrong IPv6 CIDR index collides with another subnet.
resource "aws_subnet" "public" {
  count = var.enable_ipv6_lab ? 1 : 0

  vpc_id                          = aws_vpc.lab[0].id
  availability_zone               = data.aws_availability_zones.available.names[0]
  cidr_block                      = cidrsubnet(var.lab_vpc_cidr, 8, 0)
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.lab[0].ipv6_cidr_block, 8, 0)
  assign_ipv6_address_on_creation = true

  tags = { Name = "${local.name}-ipv6-lab-public" }
}

# WHY:        Dual-stack private subnets; IPv6 pods get globally unique addresses, so no per-pod NAT is needed.
# DEPENDS:    Depends on the lab VPC.
# GOES WRONG: Pods get IPv6 only: services that are IPv4-only are unreachable without NAT64/DNS64.
resource "aws_subnet" "private" {
  count = var.enable_ipv6_lab ? 1 : 0

  vpc_id                          = aws_vpc.lab[0].id
  availability_zone               = data.aws_availability_zones.available.names[0]
  cidr_block                      = cidrsubnet(var.lab_vpc_cidr, 8, 1)
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.lab[0].ipv6_cidr_block, 8, 1)
  assign_ipv6_address_on_creation = true

  tags = { Name = "${local.name}-ipv6-lab-private" }
}

# WHY:        Routes 0.0.0.0/0 and ::/0 to the IGW.
# DEPENDS:    Depends on the IGW.
# GOES WRONG: Forgetting ::/0 breaks IPv6 egress.
resource "aws_route_table" "public" {
  count = var.enable_ipv6_lab ? 1 : 0

  vpc_id = aws_vpc.lab[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab[0].id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.lab[0].id
  }

  tags = { Name = "${local.name}-ipv6-lab-public" }
}

# WHY:        IPv6 egress for private subnets uses an EGRESS-ONLY internet gateway (outbound only, nothing inbound); this lab VPC has no IPv4 route.
# DEPENDS:    Depends on the egress-only IGW.
# GOES WRONG: Using a normal IGW exposes private pods inbound.
resource "aws_route_table" "private" {
  count = var.enable_ipv6_lab ? 1 : 0

  vpc_id = aws_vpc.lab[0].id

  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_egress_only_internet_gateway.lab[0].id
  }

  tags = { Name = "${local.name}-ipv6-lab-private" }
}

# WHY:        Associates public subnets with the public table.
# DEPENDS:    Depends on subnets + route table.
# GOES WRONG: Missing association = no route.
resource "aws_route_table_association" "public" {
  count = var.enable_ipv6_lab ? 1 : 0

  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public[0].id
}

# WHY:        Associates private subnets with the private table.
# DEPENDS:    Depends on subnets + route table.
# GOES WRONG: Missing association = no egress.
resource "aws_route_table_association" "private" {
  count = var.enable_ipv6_lab ? 1 : 0

  subnet_id      = aws_subnet.private[0].id
  route_table_id = aws_route_table.private[0].id
}
