# =============================================================================
# 30-nlb : what Terraform owns around the Network Load Balancer (static IPs)
# =============================================================================
#
#   kubectl: Service type=LoadBalancer (annotations: aws-load-balancer-type=external, nlb-target-type=ip, eip-allocations=<this folder>)
#       --> AWS Load Balancer Controller (28) --> NLB (L4) in public subnets, one EIP per AZ --> target group (pod IPs) --> Pod
#
# ALB vs NLB (interview)
#   ALB: layer 7. HTTP/HTTPS/gRPC, host/path routing, WAF, OIDC auth, redirects. Source IP seen via X-Forwarded-For. Use for web APIs.
#   NLB: layer 4. TCP/UDP/TLS, millions of connections, ultra-low latency, PRESERVES client IP, STATIC IPs per AZ, PrivateLink target.
#        Use for non-HTTP protocols, fixed IP allow-lists, or as the front of a service mesh/ingress controller.
#   Both support target-type ip (pod IPs). Both bill hourly + capacity units.
#
# WHY THE EIPs ARE HERE: an Elastic IP is an AWS resource with its own lifecycle. If the Service (and its NLB) is deleted and recreated,
# the NLB gets NEW random IPs unless you pre-allocate EIPs: customers who allow-listed the old IPs break. Owning the EIPs in Terraform
# keeps the addresses stable across NLB rebuilds.
# CLOUDCART USE: the NLB demo exposes the order-service over TCP/TLS as a contrast to the ALB path (kubernetes/ingress/nlb-service.yaml).
# COST: NLB ~$0.0225/hour + NLCU; each EIP ~$0.005/hour (~$3.65/month) allocated or not. Remove them when the lab ends.
# GOES WRONG: EIP count must equal the number of subnets in the annotation; EIP quota (default 5 per region); public IPv4 charges add up.

# WHY:        Static public IPs for the NLB so customers can allow-list them.
# DEPENDS:    Used by the NLB Service annotations.
# GOES WRONG: Unattached EIPs are billed; releasing one an external firewall relies on breaks that integration.
resource "aws_eip" "nlb" {
  for_each = var.enable_static_ips ? toset(local.azs) : toset([])

  domain = "vpc"

  tags = { Name = "${local.name}-nlb-${each.key}" }
}
