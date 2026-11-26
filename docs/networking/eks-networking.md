# EKS networking

## VPC layout
Public /24 (ALB, NAT), private /20 (nodes + pods), database /24 (no default route). Interface endpoints for ECR, STS, SSM, Secrets Manager,
SQS, Events; gateway endpoints for S3 and DynamoDB (free).

## How a Pod gets an IP (VPC CNI)
1. The node's primary ENI and extra ENIs hold secondary private IPs from the subnet.
2. `ipamd` keeps a warm pool; the CNI plugin assigns one IP per pod and wires a veth.
3. Pod IPs are REAL VPC IPs: routable, visible in flow logs, targetable by an ALB (target-type ip).
Max pods = ENIs x (IPs per ENI - 1) + 2. t3.medium = 17, m5.large = 29.

## When IPs run out
Node level: ENI/IP limits cap pods (Pending: "Too many pods"). Subnet level: no free IPs (pods stuck ContainerCreating:
`failed to assign an IP address`). Fixes: prefix delegation (/28 per slot, ~110 pods/node), larger/secondary CIDR with custom networking, IPv6.

## Prefix delegation (folder 45)
Two switches: CNI `ENABLE_PREFIX_DELEGATION=true` AND kubelet maxPods. Needs Nitro and contiguous /28 blocks.

## IPv4 vs IPv6 (folder 44)
ip_family is chosen at cluster creation. IPv6 pods have no IP exhaustion; egress via egress-only IGW; IPv4-only dependencies need DNS64/NAT64.

## Packet flows
```
Pod -> ENI -> private route table
   -> S3/DynamoDB: gateway endpoint (prefix-list route)
   -> STS/SSM/ECR: interface endpoint ENI (private DNS) in the VPC
   -> internet: NAT gateway -> IGW
Client -> Route 53 -> CloudFront -> ALB -> target group -> POD IP:8080 (no NodePort hop with target-type ip)
```

## Security groups for pods and NetworkPolicy
SGP: branch ENI + own SG (folder 43). NetworkPolicy: label-based, enforced by the CNI (folder 42). See ../security/security-model.md.

## DNS
CoreDNS answers cluster names and forwards the rest to the VPC resolver. Failure signs: `Temporary failure in name resolution`, CoreDNS pods
not Ready, SG or NetworkPolicy blocking UDP/TCP 53.
