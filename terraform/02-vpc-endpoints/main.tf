# =============================================================================
# 02-vpc-endpoints : private paths to AWS services
# =============================================================================
#
# WITHOUT endpoints                       WITH endpoints
#   Pod -> ENI -> private RT                Pod -> ENI -> private RT
#       -> NAT GW ($0.045/GB)                   -> S3/DynamoDB: gateway endpoint (FREE, prefix-list route)
#       -> IGW -> public AWS API                -> others: interface endpoint ENI (PrivateLink)
#
# GATEWAY endpoints (S3, DynamoDB): a route-table entry to an AWS-managed prefix list. Free.
# INTERFACE endpoints (everything else): an ENI with a private IP in YOUR subnet + private DNS that
#   makes sts.<region>.amazonaws.com resolve to that IP. Billed per AZ-hour + per GB.

# WHY:    Interface endpoints are reached over HTTPS from inside the VPC only.
# WHAT:   Security group allowing 443 from the whole VPC CIDR (pods, nodes, Lambda in VPC).
# GOES WRONG: if this SG blocks 443, AWS SDK calls hang until timeout (symptom: SDK "connect timeout"
#         for sts/ssm/secretsmanager while S3 works, because S3 uses the gateway endpoint).
resource "aws_security_group" "vpce" {
  name_prefix = "${local.name}-vpce-"
  description = "HTTPS from the VPC to interface VPC endpoints"
  vpc_id      = local.vpc_id

  tags = { Name = "${local.name}-vpce" }

  lifecycle {
    create_before_destroy = true
  }
}

# WHY:        Interface endpoints are ENIs in your subnets; they only answer HTTPS from the VPC CIDR.
# DEPENDS:    Depends on the endpoint security group and VPC CIDR; used by every interface endpoint (ECR, STS, Secrets Manager, ...).
# GOES WRONG: Without it pods time out calling AWS APIs (symptom: ImagePullBackOff with i/o timeout to ecr.<region>.amazonaws.com).
resource "aws_vpc_security_group_ingress_rule" "vpce_https" {
  security_group_id = aws_security_group.vpce.id
  description       = "HTTPS from VPC"
  cidr_ipv4         = local.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# FREE. Traffic to S3 (including ECR image LAYERS, which are stored in S3!) stays on the AWS network.
# NOTE: this is why ECR pulls need BOTH ecr.api/ecr.dkr interface endpoints AND the S3 gateway endpoint.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.private_route_table_ids

  tags = { Name = "${local.name}-s3" }
}

# FREE. Used by product-service (DynamoDB).
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.private_route_table_ids

  tags = { Name = "${local.name}-dynamodb" }
}

# EXPENSIVE-ISH: ~$0.01/h per endpoint per AZ (~$7.3/month) + $0.01/GB. Seven endpoints x 1 AZ ~ $51/month
# if left running. Destroy with the lab or set enable_interface_endpoints=false.
# private_dns_enabled=true is the magic: the public hostname resolves to the endpoint ENI inside the VPC.
resource "aws_vpc_endpoint" "interface" {
  for_each = var.enable_interface_endpoints ? toset(var.interface_endpoint_services) : toset([])

  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = slice(local.private_subnet_ids, 0, var.interface_endpoint_az_count)
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = { Name = "${local.name}-${replace(each.value, ".", "-")}" }
}
