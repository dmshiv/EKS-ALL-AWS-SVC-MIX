# Interview preparation

Full per-topic material (30-second, 2-minute, 5-minute, architecture, troubleshooting, production scenario, mistakes, follow-ups) is in [topics.md](topics.md). The list below is the quick-revision version.

## 30-second answers
- **How does a Pod access S3 without keys?** The ServiceAccount is bound to an IAM role by a Pod Identity association. The agent exchanges the pod token for temporary STS credentials;
  the SDK uses them. The role needs S3 and KMS permissions. Network path: S3 gateway endpoint.
- **Pod Identity vs IRSA?** Pod Identity: no OIDC provider, reusable trust, EKS API association, not on Fargate. IRSA: OIDC federation, annotation + trust per cluster, works on Fargate.
- **How does ALB reach Pods?** The controller creates the ALB from the Ingress and registers pod IPs (target-type ip) in a target group; VPC CNI pod IPs are routable.
- **Why is a Pod Pending?** `kubectl describe pod` events: insufficient resources, taints/affinity, volume AZ, IP exhaustion; Karpenter logs if it should have scaled.
- **How does Karpenter work?** It watches unschedulable pods, picks cheapest fitting EC2 via Fleet, joins nodes, consolidates and handles Spot interruption.
- **How do you secure RDS?** Isolated subnets, SG from node/pod SG, TLS, KMS, secrets in Secrets Manager with rotation, backups, deletion protection.
- **SQS vs SNS vs EventBridge?** SQS = work queue, SNS = broadcast, EventBridge = content routing; Lambda = compute.
- **How do you troubleshoot AccessDenied?** Identify the principal (`sts get-caller-identity`), the action/resource from the error, check identity policy, resource policy, KMS, SCP, via CloudTrail.

## 2-minute and 5-minute structure
Architecture (diagram) -> identity flow -> network flow -> failure mode -> how you detect it -> cost and production changes.

## Topic questions
Networking: pod IP assignment, IP exhaustion, prefix delegation, SG for pods, NetworkPolicy vs SG. Identity: trust policy, STS, access entries vs RBAC. Storage: EBS vs EFS vs S3, AZ limits.
Scaling: HPA vs Karpenter vs CA, Spot. Reliability: multi-AZ, PDB, DR, RTO/RPO. Cost: NAT, endpoints, Spot, retention. Security: layers, KMS, governance services.
Each topic has a hands-on test in USER_GUIDE.txt and a README Interview section per Terraform folder.
## Production scenarios
"Pods running but users get 5xx" (playbooks.md). "Entire cluster lost" (dr.md). "AWS bill doubled" (cost.md: Cost Explorer by Layer tag, NAT bytes, logs).
