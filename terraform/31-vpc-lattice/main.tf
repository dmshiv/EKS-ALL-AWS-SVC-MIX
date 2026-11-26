# =============================================================================
# 31-vpc-lattice : service-to-service networking (OPTIONAL, east-west traffic)
# =============================================================================
#
#   ALB / Ingress / NLB  = NORTH-SOUTH (users -> cluster).
#   VPC Lattice          = EAST-WEST  (service -> service) across clusters, VPCs and accounts, with IAM-based auth policies, without peering,
#                          transit gateway or overlapping-CIDR problems.
#
#   VPC A (this cluster)              VPC B / another cluster / Lambda / EC2
#      pod --> Lattice service DNS name --> [ SERVICE NETWORK ] --> target group (pods, instances, Lambda, ALB)
#                                              ^ VPCs are ASSOCIATED to the network; auth policy (SigV4/IAM) decides who may call what
#
# HOW IT MEETS KUBERNETES: the AWS Gateway API Controller watches Gateway API objects (Gateway, HTTPRoute) and creates the Lattice service,
# listeners and target groups; Pods become targets directly (like ALB target-type ip).
# WHEN TO USE: many services/teams/clusters/accounts needing a uniform, IAM-authorised service connectivity layer.
# WHEN NOT: a single cluster with a handful of services: a ClusterIP Service (+ NetworkPolicy) is simpler and free.
# COST: service network + association are free; you pay per Lattice SERVICE per hour and per GB/request processed => keep it disabled unless exercising it.
# This folder only creates the foundation; the controller + HTTPRoute exercise lives in USER_GUIDE.txt (section Lattice).

# WHY:        A service network is the logical boundary within which Lattice services are discoverable and authorised.
# DEPENDS:    Used by the VPC association and (optionally) the Gateway API controller.
# GOES WRONG: auth_type NONE is a lab shortcut: anyone in an associated VPC can call every service.
resource "aws_vpclattice_service_network" "this" {
  count = var.enable_lattice ? 1 : 0

  name      = "${local.name}-sn"
  auth_type = "NONE" # PRODUCTION: AWS_IAM with an auth policy per service

  tags = { Name = "${local.name}-sn" }
}

# Associating the VPC makes Lattice service DNS names resolvable and reachable from this VPC.
# PRODUCTION: also pass security_group_ids to control which clients in the VPC may call the service network.
resource "aws_vpclattice_service_network_vpc_association" "this" {
  count = var.enable_lattice ? 1 : 0

  vpc_identifier             = data.terraform_remote_state.vpc.outputs.vpc_id
  service_network_identifier = aws_vpclattice_service_network.this[0].id
}
