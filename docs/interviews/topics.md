# Interview topics (full set)

Each topic has: 30-second answer, 2-minute answer, 5-minute deep dive, architecture, a troubleshooting question, a production scenario, common mistakes and follow-up questions.

Related: [short answers](questions.md), [troubleshooting playbooks](../troubleshooting/playbooks.md), USER_GUIDE.txt for hands-on tests.


## 1. How does EKS networking work?

**30-second explanation.** Pods get real VPC IP addresses from the node's ENIs via the VPC CNI, so pod IPs are routable inside the VPC and security groups/flow logs see them.

**2-minute explanation.** The VPC CNI plugin (aws-node) attaches secondary IPs (or /28 prefixes) from the node's subnet to ENIs and assigns one per pod. Pod-to-pod traffic across nodes is plain VPC routing: no overlay. Services use kube-proxy (iptables/ipvs) for ClusterIP; ALB target-type ip registers pod IPs directly. Outbound internet goes private subnet -> NAT.

**5-minute deep explanation.** The VPC CNI plugin (aws-node) attaches secondary IPs (or /28 prefixes) from the node's subnet to ENIs and assigns one per pod. Pod-to-pod traffic across nodes is plain VPC routing: no overlay. Services use kube-proxy (iptables/ipvs) for ClusterIP; ALB target-type ip registers pod IPs directly. Outbound internet goes private subnet -> NAT. Add: max pods per node = ENIs x (IPs per ENI - 1) + 2 (or prefix-based), the subnet size consequence (/20 private subnets in 01-vpc), SG on node ENIs vs per-pod branch ENIs, DNS via CoreDNS, NetworkPolicy via the CNI eBPF agent, IPv6 clusters, and the packet flow: pod -> veth -> node ENI -> VPC router -> destination (NAT if internet).

**Architecture.** 01-vpc (subnets/NAT) -> 06-eks (CNI add-on settings) -> 45-prefix-delegation / 44-ipv6.

**Troubleshooting question.** Pod Pending with FailedCreatePodSandBox: failed to assign an IP address. How do you diagnose? Check subnet free IPs, instance ENI limits, aws-node logs, prefix delegation.

**Production scenario.** Subnets are exhausted after a scale-out. Options: prefix delegation, secondary CIDR with custom networking, larger subnets, IPv6.

**Common mistakes.** Small /24 subnets; forgetting max-pods is a node setting; assuming NetworkPolicy works without enabling the agent.

**Follow-up questions.** What happens to existing pods when you enable prefix delegation? How many pods can an m5.large run? Why is there no overlay?


## 2. How does the VPC CNI work and how does a Pod get an IP?

**30-second explanation.** aws-node (the CNI) keeps a warm pool of IPs on the node's ENIs and hands one to each new pod.

**2-minute explanation.** kubelet asks the CNI via the container runtime when a pod sandbox is created. The CNI picks an IP from the warm pool (ipamd daemon), sets up a veth pair and routes on the host, and returns the IP. ipamd allocates more ENIs/IPs ahead of demand (WARM_ENI_TARGET/WARM_IP_TARGET). IPs come from the subnet the node's ENI lives in.

**5-minute deep explanation.** kubelet asks the CNI via the container runtime when a pod sandbox is created. The CNI picks an IP from the warm pool (ipamd daemon), sets up a veth pair and routes on the host, and returns the IP. ipamd allocates more ENIs/IPs ahead of demand (WARM_ENI_TARGET/WARM_IP_TARGET). IPs come from the subnet the node's ENI lives in. Include: ENI limits per instance type, warm pool tuning cost (IPs reserved but unused), custom networking (pods in different subnets), prefix mode (/28 per slot), SG for Pods (branch ENIs via trunk), logs at /var/log/aws-routed-eni/ipamd.log.

**Architecture.** node ENI(s) -> secondary IPs/prefixes -> pods; ipamd manages the pool.

**Troubleshooting question.** A node shows plenty of CPU but new pods stay ContainerCreating: check ipamd logs, kubectl describe pod events, subnet free IPs.

**Production scenario.** During a deployment spike the warm pool cannot keep up and pods wait: tune WARM_*_TARGET or use prefix delegation.

**Common mistakes.** Over-sizing warm targets and exhausting subnets; mixing pod and node security needs without branch ENIs.

**Follow-up questions.** What is the difference between IP and prefix mode? What does ipamd do at node start?


## 3. What happens when IPs run out? What is prefix delegation?

**30-second explanation.** Pods cannot start (failed to assign IP). Prefix delegation assigns /28 blocks (16 IPs) per ENI slot, raising pod density and reducing ENI API churn.

**2-minute explanation.** Without it each ENI slot holds ONE IP. With ENABLE_PREFIX_DELEGATION=true each slot holds a /28, so a node can run far more pods (max-pods raised, typically 110/250). It needs contiguous free /28 space in the subnet and only applies to NEW nodes (see 45-prefix-delegation).

**5-minute deep explanation.** Without it each ENI slot holds ONE IP. With ENABLE_PREFIX_DELEGATION=true each slot holds a /28, so a node can run far more pods (max-pods raised, typically 110/250). It needs contiguous free /28 space in the subnet and only applies to NEW nodes (see 45-prefix-delegation). Include: fragmentation (InsufficientCidrBlocks even with free IPs: use subnet CIDR reservations), Nitro-only, interaction with SG for Pods, the alternative of custom networking/secondary CIDR (100.64.0.0/10), and IPv6 as the long-term fix.

**Architecture.** node group launch template (max-pods) + CNI add-on setting.

**Troubleshooting question.** Pods fail to get IPs after enabling prefix delegation on a fragmented subnet: look for InsufficientCidrBlocks in ipamd logs; create a CIDR reservation or new subnet.

**Production scenario.** A cluster reaches 90% of subnet IPs: add secondary CIDR + custom networking, or migrate workloads to prefix-enabled node groups with cordon/drain.

**Common mistakes.** Enabling it and expecting existing nodes to change; ignoring subnet fragmentation.

**Follow-up questions.** Why must you roll the nodes? How do you calculate max pods?


## 4. How does EKS Pod Identity work? IRSA vs Pod Identity?

**30-second explanation.** A Pod Identity association binds a ServiceAccount to an IAM role; an agent on the node vends temporary credentials. IRSA does the same with OIDC federation and annotations.

**2-minute explanation.** Pod Identity: role trusts pods.eks.amazonaws.com; you create an association (cluster, namespace, ServiceAccount, role) through the EKS API; the Pod Identity agent DaemonSet serves credentials on a link-local address, the SDK discovers them via env vars injected by the webhook; credentials are session-tagged with cluster/namespace/SA. IRSA: role trusts the cluster's OIDC provider with a sub condition; the projected token is exchanged with sts:AssumeRoleWithWebIdentity.

**5-minute deep explanation.** Pod Identity: role trusts pods.eks.amazonaws.com; you create an association (cluster, namespace, ServiceAccount, role) through the EKS API; the Pod Identity agent DaemonSet serves credentials on a link-local address, the SDK discovers them via env vars injected by the webhook; credentials are session-tagged with cluster/namespace/SA. IRSA: role trusts the cluster's OIDC provider with a sub condition; the projected token is exchanged with sts:AssumeRoleWithWebIdentity. Compare: no OIDC provider needed, trust policy reusable across clusters, no annotation, role session tags for ABAC, not supported on Fargate (use IRSA), cross-account differences, IAM role-chaining limits, SDK minimum versions.

**Architecture.** 08-pod-identity (associations) and 09-irsa (demo), roles in the data folders.

**Troubleshooting question.** Pod gets AccessDenied 'not authorized to perform sts:AssumeRoleWithWebIdentity' (IRSA): check annotation, OIDC provider, trust sub claim. For Pod Identity: check association exists, agent running, SDK version.

**Production scenario.** A multi-cluster platform wants one role definition: Pod Identity avoids editing trust policies per cluster.

**Common mistakes.** Using the node role for apps; wrong ServiceAccount name; old SDKs that ignore the container credentials endpoint.

**Follow-up questions.** Why is Pod Identity not available on Fargate? How would you prevent a pod using another team's role?


## 5. What is an IAM role trust policy and how does STS provide credentials?

**30-second explanation.** The trust policy says WHO may assume the role; STS returns temporary credentials (access key, secret, session token) that expire.

**2-minute explanation.** Two policies decide: the trust policy (resource policy on the role: principal + conditions) and the permissions policy (what the session may do). sts:AssumeRole* validates the caller against the trust policy and issues credentials with a session policy/tags, valid 15 min - 12 h. Everything we run uses assumed-role sessions, never IAM user keys.

**5-minute deep explanation.** Two policies decide: the trust policy (resource policy on the role: principal + conditions) and the permissions policy (what the session may do). sts:AssumeRole* validates the caller against the trust policy and issues credentials with a session policy/tags, valid 15 min - 12 h. Everything we run uses assumed-role sessions, never IAM user keys. Add: web identity federation (IRSA), service principals (eks, lambda), conditions (aws:SourceArn, sub), permission boundaries, SCPs, session tags, and the evaluation logic (explicit deny > allow; both identity and resource policy for cross-account).

**Architecture.** Caller -> STS -> role session -> AWS API.

**Troubleshooting question.** 'User is not authorized to perform sts:AssumeRole': fix the trust policy principal/conditions, not the permissions policy.

**Production scenario.** A leaked long-lived key was found: replace with roles, rotate, and use CloudTrail to scope the exposure.

**Common mistakes.** Putting permissions in the trust policy; wildcard principals; forgetting the caller's own permission to call AssumeRole when same-account.

**Follow-up questions.** How is cross-account assume-role different? What is an external ID?


## 6. EKS Access Entries vs aws-auth vs Kubernetes RBAC

**30-second explanation.** Access entries map IAM principals to Kubernetes permissions through the EKS API; RBAC remains the authorization model inside the cluster.

**2-minute explanation.** IAM answers 'may you call eks:*'; the access entry answers 'who are you in Kubernetes' and attaches an access policy (AmazonEKSClusterAdminPolicy...) or Kubernetes groups bound by RBAC. aws-auth ConfigMap was error-prone (one typo locks you out); access entries are API-managed and auditable.

**5-minute deep explanation.** IAM answers 'may you call eks:*'; the access entry answers 'who are you in Kubernetes' and attaches an access policy (AmazonEKSClusterAdminPolicy...) or Kubernetes groups bound by RBAC. aws-auth ConfigMap was error-prone (one typo locks you out); access entries are API-managed and auditable. Authentication mode API vs API_AND_CONFIG_MAP, the cluster creator admin permission, scoping policies to namespaces, mapping to groups for custom ClusterRoles, 07-eks-access in this repo.

**Architecture.** IAM principal -> access entry -> access policy / groups -> RBAC authorizer.

**Troubleshooting question.** kubectl returns Unauthorized vs Forbidden: Unauthorized = no entry (authn), Forbidden = entry without permission (authz).

**Production scenario.** Someone breaks aws-auth and everyone is locked out: access entries recover without cluster-internal access.

**Common mistakes.** Believing IAM permissions grant Kubernetes permissions.

**Follow-up questions.** How do you give CI deploy rights only to one namespace?


## 7. How does the ALB reach Pods? ALB vs NLB? Ingress vs Gateway API?

**30-second explanation.** The AWS Load Balancer Controller turns Ingress objects into an ALB and registers pod IPs as targets (target-type ip).

**2-minute explanation.** Controller watches Ingress/Service, creates ALB, listeners, rules and target groups, then keeps pod IPs registered (readiness gates avoid dropped requests during rollouts). ALB = L7 (HTTP routing, WAF, OIDC auth); NLB = L4 (static IPs, TLS passthrough, extreme throughput). Gateway API is the role-oriented successor to Ingress (GatewayClass/Gateway/HTTPRoute) and is supported by the controller and VPC Lattice.

**5-minute deep explanation.** Controller watches Ingress/Service, creates ALB, listeners, rules and target groups, then keeps pod IPs registered (readiness gates avoid dropped requests during rollouts). ALB = L7 (HTTP routing, WAF, OIDC auth); NLB = L4 (static IPs, TLS passthrough, extreme throughput). Gateway API is the role-oriented successor to Ingress (GatewayClass/Gateway/HTTPRoute) and is supported by the controller and VPC Lattice. Subnet tags (kubernetes.io/role/elb), security group rules node/pod from the ALB SG, instance vs ip targets, IngressGroups to share an ALB, ACM certificates, ExternalDNS, WAF association, CloudFront in front, health checks on /ready.

**Architecture.** Route 53 -> CloudFront -> WAF -> ALB -> pod IP; see architecture SVG.

**Troubleshooting question.** Ingress has no ADDRESS: controller logs; targets unhealthy: health check path/port and SG; 503 from ALB: no healthy targets.

**Production scenario.** A rollout causes brief 502s: add pod readiness gates, preStop sleep and deregistration delay alignment.

**Common mistakes.** Missing subnet tags; using instance mode with NodePort unintentionally; forgetting the SG rule from the ALB.

**Follow-up questions.** When would you choose NLB? What is the difference between IngressGroup and a new ALB per Ingress?


## 8. How does the EBS CSI driver work? EBS vs EFS?

**30-second explanation.** The CSI controller creates EBS volumes for PVCs and attaches them to the node; EBS is single-AZ block storage (RWO), EFS is shared regional NFS (RWX).

**2-minute explanation.** StorageClass (provisioner ebs.csi.aws.com, WaitForFirstConsumer) -> PVC -> controller CreateVolume in the pod's AZ -> ControllerPublish (attach) -> node plugin mounts. WaitForFirstConsumer ensures the volume is created in the AZ where the pod is scheduled. EFS uses mount targets per AZ, NFS 4.1, access points for per-app roots.

**5-minute deep explanation.** StorageClass (provisioner ebs.csi.aws.com, WaitForFirstConsumer) -> PVC -> controller CreateVolume in the pod's AZ -> ControllerPublish (attach) -> node plugin mounts. WaitForFirstConsumer ensures the volume is created in the AZ where the pod is scheduled. EFS uses mount targets per AZ, NFS 4.1, access points for per-app roots. Include snapshots (VolumeSnapshot), expansion, encryption with KMS, volume lifecycle (reclaimPolicy), AZ pinning problems after node loss, EFS throughput modes and cost, small-file performance, SG 2049.

**Architecture.** 13-ebs / 14-efs / kubernetes/storage.

**Troubleshooting question.** Pod stuck ContainerCreating with 'volume node affinity conflict' or attach errors: AZ mismatch; with EFS: mount timeout = SG or missing mount target.

**Production scenario.** A stateful workload must survive an AZ failure: EBS cannot; use EFS, replication at the app layer, or backups with restore into another AZ.

**Common mistakes.** Immediate binding creating volumes in the wrong AZ; forgetting KMS permissions for the CSI role.

**Follow-up questions.** How do you migrate data between AZs? When is S3 better than both?


## 9. Why is a Pod Pending?

**30-second explanation.** The scheduler cannot place it: insufficient resources, taints/affinity, unbound PVC, or no capacity/IPs.

**2-minute explanation.** kubectl describe pod -> Events: FailedScheduling message lists per-node reasons (Insufficient cpu, node(s) had untolerated taint, volume node affinity conflict). If nothing fits, Karpenter/Cluster Autoscaler should add capacity: check their logs and the NodePool limits.

**5-minute deep explanation.** kubectl describe pod -> Events: FailedScheduling message lists per-node reasons (Insufficient cpu, node(s) had untolerated taint, volume node affinity conflict). If nothing fits, Karpenter/Cluster Autoscaler should add capacity: check their logs and the NodePool limits. Walk through requests vs allocatable, PodDisruptionBudgets, topology spread, PVC AZ, quotas/LimitRange, priority and preemption, and the difference between Pending (unscheduled) and ContainerCreating (scheduled).

**Architecture.** Pod -> scheduler -> (Karpenter NodeClaim) -> node -> kubelet.

**Troubleshooting question.** As above; USER_GUIDE section 30/32 reproduce each case.

**Production scenario.** A deploy hangs at 50%: a PDB or quota prevents rollout; show the evidence chain.

**Common mistakes.** Debugging the app when the pod never started; ignoring Events.

**Follow-up questions.** How does Karpenter decide the instance type?


## 10. How does Karpenter work? Karpenter vs Cluster Autoscaler?

**30-second explanation.** Karpenter watches unschedulable pods and launches right-sized EC2 instances directly through the EC2 Fleet API; CA scales pre-defined node groups.

**2-minute explanation.** NodePool defines constraints (requirements, limits, disruption), EC2NodeClass defines AWS specifics (AMI, subnets, SGs, role). Provisioning: batch pending pods, compute the cheapest fitting instance set, create NodeClaims, nodes join and pods schedule. Consolidation replaces/removes underutilised nodes; interruption queue handles Spot events.

**5-minute deep explanation.** NodePool defines constraints (requirements, limits, disruption), EC2NodeClass defines AWS specifics (AMI, subnets, SGs, role). Provisioning: batch pending pods, compute the cheapest fitting instance set, create NodeClaims, nodes join and pods schedule. Consolidation replaces/removes underutilised nodes; interruption queue handles Spot events. Contrast: CA is ASG-based, slower, one instance type per group; Karpenter picks across types/AZs/capacity types, supports consolidation and drift. Include Spot diversification, disruption budgets, PDBs, `do-not-disrupt`, running Karpenter on a managed node group or Fargate (not on its own nodes), IAM (controller + node role), discovery tags.

**Architecture.** 12-karpenter + kubernetes/karpenter (NodePool/EC2NodeClass).

**Troubleshooting question.** Pods Pending but no NodeClaim: controller logs (no matching subnets, limits reached, insufficient capacity, AccessDenied).

**Production scenario.** Spot interruption mid-peak: interruption queue drains nodes with 2-minute notice; PDBs and replicas protect availability.

**Common mistakes.** No limits on NodePool (cost runaway); too narrow instance requirements (no capacity); disabling consolidation forever.

**Follow-up questions.** How would you cap cost? How do you keep critical pods off Spot?


## 11. How do Pods access S3?

**30-second explanation.** Through an IAM role assumed via Pod Identity/IRSA; the SDK gets temporary credentials, and requests go through the S3 gateway endpoint in the VPC.

**2-minute explanation.** ServiceAccount -> association -> role with a least-privilege policy on one bucket/prefix (+ KMS). Bucket policy enforces TLS and restricts principals. Traffic: private subnet -> S3 gateway VPC endpoint (free) instead of NAT.

**5-minute deep explanation.** ServiceAccount -> association -> role with a least-privilege policy on one bucket/prefix (+ KMS). Bucket policy enforces TLS and restricts principals. Traffic: private subnet -> S3 gateway VPC endpoint (free) instead of NAT. Both identity and resource policies must allow; KMS adds a third check; versioning, lifecycle, public access block, endpoint policy as additional guardrail, presigned URLs for browser uploads.

**Architecture.** 15-s3 + 02-vpc-endpoints + 08-pod-identity.

**Troubleshooting question.** AccessDenied: read the error (principal/action/resource), `aws sts get-caller-identity` inside the pod, check identity policy, bucket policy, KMS, endpoint policy; CloudTrail shows the denied event.

**Production scenario.** Large downloads inflate NAT cost: confirm the gateway endpoint route exists.

**Common mistakes.** Static keys in env vars; wildcard resources; forgetting kms:GenerateDataKey.

**Follow-up questions.** Why does a gateway endpoint cost nothing while interface endpoints do?


## 12. How does a Pod connect to RDS? How do you secure RDS?

**30-second explanation.** Over private networking: pod -> node/pod SG -> RDS SG (SG-to-SG rule) in isolated subnets, credentials from Secrets Manager.

**2-minute explanation.** RDS in database subnets with no internet route, security group allowing 5432 only from the node SG (or a dedicated pod SG), storage encrypted with KMS, TLS enforced, credentials in Secrets Manager read at runtime by the pod role, backups + PITR, Multi-AZ, deletion protection, connection pooling (RDS Proxy or app pool).

**5-minute deep explanation.** RDS in database subnets with no internet route, security group allowing 5432 only from the node SG (or a dedicated pod SG), storage encrypted with KMS, TLS enforced, credentials in Secrets Manager read at runtime by the pod role, backups + PITR, Multi-AZ, deletion protection, connection pooling (RDS Proxy or app pool). Add: rotation, IAM database authentication, parameter groups (force SSL), enhanced monitoring, snapshot copy for DR, failover behaviour (DNS flip ~60-120 s, connection retry required).

**Architecture.** 19-rds + 17-secrets-manager + 03-security-groups (+ 43 for per-pod SG).

**Troubleshooting question.** Timeout (SG/route) vs 'password authentication failed' (secret) vs 'too many connections' (pooling): different layers, different fixes.

**Production scenario.** A failover occurs and the app does not recover: DNS caching and connection pool validation.

**Common mistakes.** Public accessibility enabled; CIDR rules instead of SG references; secrets in env files.

**Follow-up questions.** RDS vs Aurora? When do you add RDS Proxy?


## 13. SQS vs SNS vs EventBridge (and Lambda)

**30-second explanation.** SQS = queue (one consumer group pulls work), SNS = pub/sub fan-out (push), EventBridge = event bus with content-based routing; Lambda = compute that reacts.

**2-minute explanation.** Use SQS to decouple and buffer work with retries and DLQ; SNS to broadcast one message to many subscribers (including SQS queues); EventBridge to route events by pattern from many sources, schedule, and integrate SaaS/AWS service events. Combine: EventBridge -> Lambda -> SNS -> SQS consumers as in this project.

**5-minute deep explanation.** Use SQS to decouple and buffer work with retries and DLQ; SNS to broadcast one message to many subscribers (including SQS queues); EventBridge to route events by pattern from many sources, schedule, and integrate SaaS/AWS service events. Combine: EventBridge -> Lambda -> SNS -> SQS consumers as in this project. Delivery semantics (at-least-once, FIFO dedupe), ordering, retention, DLQs and redrive, throughput limits, filtering, cost per request, idempotent consumers, visibility timeout vs processing time.

**Architecture.** 22-sqs, 23-sns, 24-eventbridge, 25-lambda.

**Troubleshooting question.** Messages processed twice: visibility timeout too short or missing delete; messages in DLQ: poison message or permissions.

**Production scenario.** Traffic spike: SQS absorbs it, workers scale on queue depth (KEDA/HPA with external metric).

**Common mistakes.** Assuming exactly-once; no DLQ alarm; SNS to SQS without queue policy.

**Follow-up questions.** When would you pick Kinesis instead? How do you replay events?


## 14. How do you troubleshoot AccessDenied?

**30-second explanation.** Identify the principal, the action and resource from the error, then check each policy layer in order.

**2-minute explanation.** 1) Who am I (sts get-caller-identity from the pod). 2) Exact action/resource in the error. 3) Identity policy. 4) Resource policy (bucket/queue/key). 5) KMS key policy/grants. 6) Permission boundary/SCP. 7) VPC endpoint policy. CloudTrail errorCode AccessDenied shows the evaluated principal.

**5-minute deep explanation.** 1) Who am I (sts get-caller-identity from the pod). 2) Exact action/resource in the error. 3) Identity policy. 4) Resource policy (bucket/queue/key). 5) KMS key policy/grants. 6) Permission boundary/SCP. 7) VPC endpoint policy. CloudTrail errorCode AccessDenied shows the evaluated principal. Explicit deny wins; both sides for cross-account; session policies; condition keys (aws:SourceVpce, ResourceTag); IAM policy simulator and Access Analyzer; encoded error messages (sts decode-authorization-message).

**Architecture.** Identity -> policy evaluation -> resource.

**Troubleshooting question.** The S3 injection test in USER_GUIDE 14 and Secrets Manager test in 15.

**Production scenario.** A new service cannot read its secret after a deploy: wrong role name in the association.

**Common mistakes.** Editing policies randomly; forgetting the KMS layer.

**Follow-up questions.** Which policy types are evaluated for a same-account request?


## 15. How do you troubleshoot ImagePullBackOff?

**30-second explanation.** Read the pod event: it distinguishes 'not found', 'no basic auth credentials' and 'i/o timeout'.

**2-minute explanation.** not found = wrong repo/tag; no basic auth = node role lacks ECR read; i/o timeout = no route to ECR (NAT/VPC endpoints) or SG blocks 443; also S3 gateway endpoint needed for layers. Verify: aws ecr describe-images, node role policy, endpoints, then docker pull from a node/pod.

**5-minute deep explanation.** not found = wrong repo/tag; no basic auth = node role lacks ECR read; i/o timeout = no route to ECR (NAT/VPC endpoints) or SG blocks 443; also S3 gateway endpoint needed for layers. Verify: aws ecr describe-images, node role policy, endpoints, then docker pull from a node/pod. Immutable tags, ECR pull-through cache, cross-account repository policy, imagePullSecrets for non-ECR registries, rate limits for Docker Hub.

**Architecture.** 04-ecr + 05-iam + 02-vpc-endpoints.

**Troubleshooting question.** Event text first; then ecr describe-images; then network.

**Production scenario.** Production deploy with a tag that was never pushed: block deploys via CI gate.

**Common mistakes.** Using :latest and getting different images on different nodes.

**Follow-up questions.** Why does ECR need the S3 gateway endpoint?


## 16. How do you troubleshoot CrashLoopBackOff / OOMKilled?

**30-second explanation.** kubectl logs --previous and describe: exit code and Last State tell you whether the app crashed or was killed.

**2-minute explanation.** Exit 1/2 = app error (config, missing secret, dependency); 137 + OOMKilled = memory limit; 143 = SIGTERM (probe/rollout); liveness probe failures also restart. Check events, previous logs, resource limits, probe settings.

**5-minute deep explanation.** Exit 1/2 = app error (config, missing secret, dependency); 137 + OOMKilled = memory limit; 143 = SIGTERM (probe/rollout); liveness probe failures also restart. Check events, previous logs, resource limits, probe settings. Startup probes for slow apps, requests vs limits, JVM/heap sizing, memory leaks, init containers.

**Architecture.** Pod -> container -> restart policy backoff.

**Troubleshooting question.** USER_GUIDE 30.1 reproduces both.

**Production scenario.** A deployment restarts every 10 minutes: memory growth reaches the limit.

**Common mistakes.** Raising limits without finding the leak; liveness probe too aggressive.

**Follow-up questions.** What is the difference between a liveness and readiness failure in user impact?


## 17. How do you troubleshoot DNS?

**30-second explanation.** Check CoreDNS pods, resolv.conf in the pod, then test an internal and an external name separately.

**2-minute explanation.** kubectl exec pod -- nslookup kubernetes.default and nslookup amazon.com; CoreDNS logs; NetworkPolicy/SG blocking UDP/TCP 53; ndots:5 causing slow lookups; VPC DNS resolver limits (1024 pps per ENI); for Route 53/ACM: delegation of NS at the registrar and propagation.

**5-minute deep explanation.** kubectl exec pod -- nslookup kubernetes.default and nslookup amazon.com; CoreDNS logs; NetworkPolicy/SG blocking UDP/TCP 53; ndots:5 causing slow lookups; VPC DNS resolver limits (1024 pps per ENI); for Route 53/ACM: delegation of NS at the registrar and propagation. NodeLocal DNSCache, CoreDNS scaling, private hosted zones, ExternalDNS, conditional forwarding.

**Architecture.** Pod -> CoreDNS -> VPC resolver -> Route 53.

**Troubleshooting question.** Intermittent timeouts at scale: hit the per-ENI limit; add NodeLocal DNS.

**Production scenario.** Egress NetworkPolicy blocking DNS.

**Common mistakes.** Blaming the app; testing only external names.

**Follow-up questions.** Why does ndots:5 hurt performance?


## 18. How do you troubleshoot an ALB?

**30-second explanation.** Follow the path: Ingress ADDRESS -> listener/rule -> target group health -> SG -> pod readiness.

**2-minute explanation.** kubectl describe ingress (events), controller logs, aws elbv2 describe-target-health, ALB access logs and CloudWatch 5xx metrics. 502 = bad response from target; 503 = no healthy targets; 504 = timeout (SG/idle timeout); 403 = WAF.

**5-minute deep explanation.** kubectl describe ingress (events), controller logs, aws elbv2 describe-target-health, ALB access logs and CloudWatch 5xx metrics. 502 = bad response from target; 503 = no healthy targets; 504 = timeout (SG/idle timeout); 403 = WAF. Subnet tags, SG from ALB to pods, health check path, readiness gates, WAF in count mode, cert/hostname mismatch, CloudFront origin settings.

**Architecture.** Route53 -> CloudFront -> WAF -> ALB -> Service -> Pod.

**Troubleshooting question.** USER_GUIDE section 24.

**Production scenario.** Users see 502s only during deploys: draining and readiness gates.

**Common mistakes.** Health check on '/' that redirects (301) -> unhealthy.

**Follow-up questions.** Why target-type ip needs pod SG rules, not just node SG?


## 19. How do you design multi-AZ EKS?

**30-second explanation.** Spread nodes, subnets, NAT, data stores and replicas across at least 2-3 AZs and enforce spread with topology constraints.

**2-minute explanation.** Private subnets per AZ, one NAT per AZ (production), managed node groups in all AZs, topologySpreadConstraints and PDBs, Multi-AZ RDS/ElastiCache, EFS (regional), EBS-aware scheduling (volumes are AZ-bound), ALB across AZs, Karpenter with multiple AZ subnets.

**5-minute deep explanation.** Private subnets per AZ, one NAT per AZ (production), managed node groups in all AZs, topologySpreadConstraints and PDBs, Multi-AZ RDS/ElastiCache, EFS (regional), EBS-aware scheduling (volumes are AZ-bound), ALB across AZs, Karpenter with multiple AZ subnets. Zonal shift/ARC, cross-zone load balancing cost, data transfer between AZs, capacity per AZ for failover (N+1), DynamoDB/S3 are regional.

**Architecture.** 01-vpc (subnets per AZ) -> 10-node-groups -> 12-karpenter.

**Troubleshooting question.** One AZ degraded: cordon nodes in that AZ and verify headroom in others.

**Production scenario.** AZ outage: pods reschedule only if capacity and PVC AZ allow.

**Common mistakes.** Single NAT in lab copied to production; stateful pods pinned to one AZ.

**Follow-up questions.** How do you test AZ failure?


## 20. How do you design DR?

**30-second explanation.** Define RTO/RPO first, then pick backup/restore, pilot light, warm standby or active-active; keep infrastructure reproducible in Terraform.

**2-minute explanation.** Data: AWS Backup with cross-region copy, RDS snapshots/replicas, DynamoDB PITR/global tables, S3 replication, ECR replication; compute: Terraform + Helm/GitOps recreate the cluster; DNS failover with Route 53 health checks; secrets/KMS multi-region keys.

**5-minute deep explanation.** Data: AWS Backup with cross-region copy, RDS snapshots/replicas, DynamoDB PITR/global tables, S3 replication, ECR replication; compute: Terraform + Helm/GitOps recreate the cluster; DNS failover with Route 53 health checks; secrets/KMS multi-region keys. Test restores regularly, runbooks, dependency order, region-specific resources (ACM certificates, endpoints), cost of standby, state bucket replication.

**Architecture.** 40-backup + docs/disaster-recovery/dr.md.

**Troubleshooting question.** A restore test fails because KMS key not available in the DR region: multi-region keys.

**Production scenario.** Region outage: how long until service is back, what data is lost.

**Common mistakes.** Untested backups; DR plan that depends on the failed region.

**Follow-up questions.** What is your RTO/RPO for CloudCart and how do you prove it?


## 21. How do you reduce EKS costs?

**30-second explanation.** Right-size, use Spot via Karpenter, consolidate, cut NAT/data transfer with endpoints, shorten log retention, delete idle resources.

**2-minute explanation.** Biggest drivers: EC2, NAT data processing, load balancers, EBS/EFS, CloudWatch logs, inter-AZ traffic. Use Savings Plans for baseline, Spot for stateless, Graviton, VPA/requests tuning, gateway endpoints for S3/DynamoDB, ECR lifecycle, tagging for Cost Explorer.

**5-minute deep explanation.** Biggest drivers: EC2, NAT data processing, load balancers, EBS/EFS, CloudWatch logs, inter-AZ traffic. Use Savings Plans for baseline, Spot for stateless, Graviton, VPA/requests tuning, gateway endpoints for S3/DynamoDB, ECR lifecycle, tagging for Cost Explorer. Karpenter consolidation, scheduled scale-down of dev, one NAT in non-prod, fewer interface endpoints in labs, Fargate only where it pays, Container Insights costs.

**Architecture.** docs/cost/cost.md; scripts/cost-check.sh.

**Troubleshooting question.** Bill doubled: Cost Explorer by tag/service, NAT bytes, log ingestion.

**Production scenario.** Always-on lab left running: budgets and cleanup order.

**Common mistakes.** Over-provisioned requests; no log retention.

**Follow-up questions.** How do you attribute cost per team?


## 22. How do you secure EKS?

**30-second explanation.** Layer it: IAM least privilege, private networking, encryption, workload hardening, network policy, detection and audit.

**2-minute explanation.** Control plane: private/limited endpoint, audit logs, KMS secrets encryption, access entries. Nodes: minimal AMI, IMDSv2 hop limit, no SSH. Workloads: non-root, read-only FS, Pod Security Standards, resource limits, signed/scanned immutable images. Network: SGs, NetworkPolicy, WAF. Identity: Pod Identity/IRSA, no static keys. Detection: CloudTrail, GuardDuty (audit log + runtime), Config, Security Hub.

**5-minute deep explanation.** Control plane: private/limited endpoint, audit logs, KMS secrets encryption, access entries. Nodes: minimal AMI, IMDSv2 hop limit, no SSH. Workloads: non-root, read-only FS, Pod Security Standards, resource limits, signed/scanned immutable images. Network: SGs, NetworkPolicy, WAF. Identity: Pod Identity/IRSA, no static keys. Detection: CloudTrail, GuardDuty (audit log + runtime), Config, Security Hub. Supply chain (ECR scanning, admission policy), secrets from Secrets Manager via CSI/SDK, RBAC reviews, SCPs, break-glass access, patching cadence.

**Architecture.** docs/security/security-model.md.

**Troubleshooting question.** Finding: privileged pod launched -> GuardDuty -> investigate with audit logs.

**Production scenario.** Compromised pod: what can it reach? Limit with IAM scope, NetworkPolicy and IMDS blocking.

**Common mistakes.** Cluster admin for everyone; node role with app permissions; open public endpoint.

**Follow-up questions.** How do you prevent a pod from using the node role via IMDS?


## 23. Docker image lifecycle and ECR

**30-second explanation.** Source -> Dockerfile -> build -> scan -> tag (immutable) -> push to ECR -> EKS pulls with the node role.

**2-minute explanation.** Multi-stage builds, non-root user, pinned dependencies, .dockerignore, HEALTHCHECK/probes. Push: aws ecr get-login-password | docker login; docker push repo:tag. ECR immutable tags, lifecycle policy, scan on push, KMS encryption. Nodes pull using the node role (ecr:GetAuthorizationToken + read) over NAT or VPC endpoints.

**5-minute deep explanation.** Multi-stage builds, non-root user, pinned dependencies, .dockerignore, HEALTHCHECK/probes. Push: aws ecr get-login-password | docker login; docker push repo:tag. ECR immutable tags, lifecycle policy, scan on push, KMS encryption. Nodes pull using the node role (ecr:GetAuthorizationToken + read) over NAT or VPC endpoints. Digest pinning, SBOM/signing, pull-through cache, cross-region replication, CI with OIDC (46-cicd), why :latest is unsafe (non-reproducible, rollbacks impossible).

**Architecture.** application/ -> 04-ecr -> kubernetes/helm.

**Troubleshooting question.** ImagePullBackOff playbook above.

**Production scenario.** Rollback to the previous tag works because tags are immutable.

**Common mistakes.** Mutable tags; running as root; no scanning.

**Follow-up questions.** Tag vs digest: which is safer?


## 24. Observability: logs, metrics, traces

**30-second explanation.** Logs tell what happened, metrics tell how much/how often, traces tell where time was spent; CloudWatch and Container Insights collect them.

**2-minute explanation.** Container Insights (CloudWatch agent + Fluent Bit) gives cluster/pod metrics and logs; app logs to stdout as JSON; custom metrics/alarms (queue age, DLQ depth, 5xx); X-Ray/OpenTelemetry for traces; CloudTrail for AWS API audit.

**5-minute deep explanation.** Container Insights (CloudWatch agent + Fluent Bit) gives cluster/pod metrics and logs; app logs to stdout as JSON; custom metrics/alarms (queue age, DLQ depth, 5xx); X-Ray/OpenTelemetry for traces; CloudTrail for AWS API audit. Retention and cost, log-based metric filters, alarm design (symptom-based), SLOs, dashboards, correlation IDs.

**Architecture.** 34-cloudwatch + 35-container-insights + 36-cloudtrail.

**Troubleshooting question.** Latency spike: metrics find when, traces find where, logs find why.

**Production scenario.** DLQ grows silently: alarm on ApproximateNumberOfMessagesVisible.

**Common mistakes.** Alerting on causes (CPU) instead of symptoms; unbounded log retention.

**Follow-up questions.** What is the difference between Container Insights and Prometheus?


## 25. Security services: GuardDuty, Security Hub, Config, CloudTrail, KMS, WAF

**30-second explanation.** CloudTrail records API calls, Config records resource state and compliance, GuardDuty detects threats, Security Hub aggregates, KMS encrypts, WAF filters HTTP.

**2-minute explanation.** Each answers a different question: who did what (CloudTrail), what changed and is it compliant (Config), is someone attacking (GuardDuty), what is the overall posture (Security Hub), who can decrypt (KMS), is this request malicious (WAF). They are detective unless stated; none replaces least privilege.

**5-minute deep explanation.** Each answers a different question: who did what (CloudTrail), what changed and is it compliant (Config), is someone attacking (GuardDuty), what is the overall posture (Security Hub), who can decrypt (KMS), is this request malicious (WAF). They are detective unless stated; none replaces least privilege. Costs and noise, multi-account aggregation, automated remediation (EventBridge + Lambda/SSM), key policies and grants, WAF managed rules/count mode, regional vs CloudFront scope.

**Architecture.** 33, 36, 37, 38, 39 and 16-kms.

**Troubleshooting question.** WAF blocks legitimate traffic: review sampled requests and switch the rule to count.

**Production scenario.** Security Hub shows hundreds of findings: prioritise by severity, suppress accepted risks.

**Common mistakes.** Enabling everything without owners for findings.

**Follow-up questions.** Which of these are preventive?


## 26. Terraform state dependencies and execution order

**30-second explanation.** Each folder has its own state; later folders read earlier outputs with terraform_remote_state, and a script enforces the apply order.

**2-minute explanation.** State per folder in S3 (native locking, encryption, versioning) limits blast radius and speeds plans. Outputs are the contract between folders; scripts/tf.sh derives upstream folders from the code, checks their state and outputs exist, then init/validate/plan/apply and verify. The one numeric exception is 16-kms right after 03.

**5-minute deep explanation.** State per folder in S3 (native locking, encryption, versioning) limits blast radius and speeds plans. Outputs are the contract between folders; scripts/tf.sh derives upstream folders from the code, checks their state and outputs exist, then init/validate/plan/apply and verify. The one numeric exception is 16-kms right after 03. Why not one big state (blast radius, lock contention, plan time), why not too many (output sprawl), partial backend config, bootstrap chicken-and-egg (local state first, then migrate), drift detection, destroy in reverse order.

**Architecture.** docs/architecture + scripts/execution-order.txt.

**Troubleshooting question.** 'upstream state missing' or 'output not found' after destroying a folder out of order.

**Production scenario.** Changing an output name breaks downstream plans: check-wiring.py catches it.

**Common mistakes.** Hard-coded IDs; applying out of order; sharing one state across teams.

**Follow-up questions.** How do you migrate state between backends? What does use_lockfile replace?


## 27. Storage and databases: DynamoDB, ElastiCache, RDS vs Aurora

**30-second explanation.** DynamoDB for key-value access at any scale, Redis for caching/sessions, RDS/Aurora for relational transactions.

**2-minute explanation.** DynamoDB: design by access pattern, partition key spread, on-demand vs provisioned, PITR, IAM per table. ElastiCache: cache-aside pattern, TTLs, auth token + TLS, failure behaviour (app must tolerate cache loss). RDS: Multi-AZ, backups, parameter groups; Aurora: shared storage, faster failover, readers, higher cost.

**5-minute deep explanation.** DynamoDB: design by access pattern, partition key spread, on-demand vs provisioned, PITR, IAM per table. ElastiCache: cache-aside pattern, TTLs, auth token + TLS, failure behaviour (app must tolerate cache loss). RDS: Multi-AZ, backups, parameter groups; Aurora: shared storage, faster failover, readers, higher cost. Hot partitions, GSIs, consistency, cache stampede, connection limits, failover, backup retention, cost drivers.

**Architecture.** 19-rds, 20-dynamodb, 21-elasticache.

**Troubleshooting question.** Throttling vs AccessDenied vs timeout: each points to a different layer.

**Production scenario.** Redis down: the app must degrade to the database, not fail.

**Common mistakes.** Using DynamoDB like SQL; caching without TTL.

**Follow-up questions.** When would you pick Aurora over RDS?


## 28. Scaling: HPA, Karpenter, Spot, Fargate, Cluster Autoscaler

**30-second explanation.** HPA scales pods, Karpenter/CA scale nodes, Spot cuts cost with interruption risk, Fargate removes node management at higher per-pod cost.

**2-minute explanation.** HPA on CPU/memory/custom metrics needs metrics-server; Pending pods trigger Karpenter; consolidation scales down; Spot requires stateless pods, PDBs and diversified instance types; Fargate for isolated bursty pods (no DaemonSets, no Pod Identity).

**5-minute deep explanation.** HPA on CPU/memory/custom metrics needs metrics-server; Pending pods trigger Karpenter; consolidation scales down; Spot requires stateless pods, PDBs and diversified instance types; Fargate for isolated bursty pods (no DaemonSets, no Pod Identity). KEDA for queue-based scaling, HPA/VPA conflict, scale-down delays, PDB blocking drain, node startup time, over-provisioning with low-priority pods.

**Architecture.** 41-autoscaling, 12-karpenter, 11-fargate.

**Troubleshooting question.** HPA shows <unknown> metrics: metrics-server not installed or no requests set.

**Production scenario.** Flash sale: pods scale first, nodes second; pre-warm if startup latency matters.

**Common mistakes.** No resource requests (HPA cannot compute); Spot for stateful pods.

**Follow-up questions.** How does the scheduler interact with HPA and Karpenter?


## 29. Networking: Security Groups, NetworkPolicy, Security Groups for Pods

**30-second explanation.** SGs filter at the ENI by IP/SG, NetworkPolicy filters pod-to-pod by labels on the node, SG for Pods gives a pod its own SG via a branch ENI.

**2-minute explanation.** Node SG applies to all pods on the node. SG for Pods (trunk/branch ENIs, supported instances) lets only selected pods reach RDS. NetworkPolicy (VPC CNI eBPF agent) implements default deny and allow rules; IAM/RBAC are separate layers.

**5-minute deep explanation.** Node SG applies to all pods on the node. SG for Pods (trunk/branch ENIs, supported instances) lets only selected pods reach RDS. NetworkPolicy (VPC CNI eBPF agent) implements default deny and allow rules; IAM/RBAC are separate layers. Where each operates, DNS egress needs, SG reference rules, NACLs stateless, flow logs, cost/limits of branch ENIs.

**Architecture.** 03-security-groups, 42-network-policies, 43-security-groups-for-pods.

**Troubleshooting question.** Timeout between pods after default-deny: add allow rules including DNS.

**Production scenario.** Compliance wants only the order service to reach RDS: SG for Pods.

**Common mistakes.** Assuming NetworkPolicy blocks AWS API calls (it does not: IAM/SG/endpoint do).

**Follow-up questions.** Why do SG for Pods need specific instance types?


## 30. EKS compute: Managed Node Groups, Fargate, Karpenter

**30-second explanation.** Managed node groups are simple ASG-backed nodes with AWS-managed lifecycle; Karpenter is dynamic and cost-optimising; Fargate is serverless per-pod.

**2-minute explanation.** Use a small managed node group for system components (CoreDNS, Karpenter), Karpenter for application capacity (On-Demand + Spot), Fargate selectively. Upgrades: managed rolling updates vs Karpenter drift.

**5-minute deep explanation.** Use a small managed node group for system components (CoreDNS, Karpenter), Karpenter for application capacity (On-Demand + Spot), Fargate selectively. Upgrades: managed rolling updates vs Karpenter drift. AMI types, launch templates, max-pods, taints, labels, update config, DaemonSet overhead, Graviton.

**Architecture.** 10-node-groups, 11-fargate, 12-karpenter.

**Troubleshooting question.** Nodes not joining: node role mapping/access entry, SG/route to endpoint, bootstrap user data.

**Production scenario.** Kubernetes version upgrade: control plane first, then nodes, check deprecated APIs.

**Common mistakes.** Running Karpenter on nodes it manages.

**Follow-up questions.** How do you upgrade nodes with zero downtime?


## 31. Route 53, ACM and TLS

**30-second explanation.** Route 53 resolves names, ACM issues and renews certificates after DNS validation, the load balancer/CloudFront terminates TLS.

**2-minute explanation.** Hosted zone + delegated NS; ACM certificate (regional for ALB, us-east-1 for CloudFront); DNS validation CNAME; Terraform waits for ISSUED; ExternalDNS or Terraform creates alias records.

**5-minute deep explanation.** Hosted zone + delegated NS; ACM certificate (regional for ALB, us-east-1 for CloudFront); DNS validation CNAME; Terraform waits for ISSUED; ExternalDNS or Terraform creates alias records. TLS policies, redirect HTTP to HTTPS, end-to-end TLS to pods, renewal behaviour, private vs public zones, health checks and failover routing.

**Architecture.** 26-route53, 27-acm, 29-alb, 32-cloudfront.

**Troubleshooting question.** Certificate PENDING_VALIDATION: record not in the public zone or NS not delegated.

**Production scenario.** Domain moved registrars: validation records are lost if NS changes.

**Common mistakes.** Certificate in wrong region; forgetting the validation record.

**Follow-up questions.** How does ACM renewal work?


## 32. Messaging: reliability patterns (retries, DLQ, idempotency)

**30-second explanation.** At-least-once delivery means consumers must be idempotent; retries and a DLQ isolate poison messages.

**2-minute explanation.** SQS visibility timeout > processing time; maxReceiveCount then DLQ; the worker deletes only after success; idempotency key (order id) in the database; alarms on DLQ depth and oldest message age; scale workers on queue depth.

**5-minute deep explanation.** SQS visibility timeout > processing time; maxReceiveCount then DLQ; the worker deletes only after success; idempotency key (order id) in the database; alarms on DLQ depth and oldest message age; scale workers on queue depth. Partial batch failures, FIFO ordering, backoff with jitter, redrive, poison messages, observability.

**Architecture.** 22-sqs, worker code in application/services/worker.

**Troubleshooting question.** Messages loop forever: visibility timeout too short or error never acknowledged.

**Production scenario.** Payment event processed twice: idempotency saves the day.

**Common mistakes.** Deleting before processing; no DLQ monitoring.

**Follow-up questions.** How would you handle ordering requirements?


## 33. Backup, KMS and Secrets Manager

**30-second explanation.** Backups protect against data loss, KMS controls who can decrypt, Secrets Manager stores and rotates credentials accessed by IAM role.

**2-minute explanation.** AWS Backup plans by tag with retention and cross-region copy; CMKs per data domain with key policies; secrets encrypted with the CMK, read at runtime (no Kubernetes Secret values in Git); rotation.

**5-minute deep explanation.** AWS Backup plans by tag with retention and cross-region copy; CMKs per data domain with key policies; secrets encrypted with the CMK, read at runtime (no Kubernetes Secret values in Git); rotation. Key deletion window risks, grants for service principals, secret rotation Lambdas, Parameter Store for non-secrets, cost per secret/key.

**Architecture.** 16-kms, 17-secrets-manager, 18-parameter-store, 40-backup.

**Troubleshooting question.** AccessDenied on GetSecretValue: identity policy or kms:Decrypt missing.

**Production scenario.** Rotating the DB password: app must re-read; test with the failure scenario.

**Common mistakes.** Storing secrets in ConfigMaps; scheduling key deletion by accident.

**Follow-up questions.** Secrets Manager vs Parameter Store SecureString?


## 34. Terraform vs Kubernetes: where does each resource belong?

**30-second explanation.** Terraform owns AWS infrastructure and platform add-ons; Helm/GitOps own application workloads that change with every release.

**2-minute explanation.** AWS resources with lifecycle independent of pods (VPC, EKS, RDS, IAM roles) belong in Terraform; Deployments, Services, HPA, NetworkPolicies per service belong to Helm/Argo CD. Boundary objects (Pod Identity associations, add-ons, namespace baseline policies) are Terraform because they involve AWS APIs.

**5-minute deep explanation.** AWS resources with lifecycle independent of pods (VPC, EKS, RDS, IAM roles) belong in Terraform; Deployments, Services, HPA, NetworkPolicies per service belong to Helm/Argo CD. Boundary objects (Pod Identity associations, add-ons, namespace baseline policies) are Terraform because they involve AWS APIs. Avoid managing the same object in both, drift, state size, the Kubernetes/Helm providers needing a live cluster (separate folders).

**Architecture.** terraform/ vs kubernetes/ + helm/ + 47-gitops.

**Troubleshooting question.** Resource flapping: two tools managing one object.

**Production scenario.** A new microservice: Helm values, not Terraform, except its IAM role.

**Common mistakes.** Putting application Deployments into the cluster folder.

**Follow-up questions.** How does Argo CD handle drift?


## 35. Gateway API, VPC Lattice and CloudFront

**30-second explanation.** Gateway API is the successor to Ingress, VPC Lattice provides service-to-service networking across VPCs, CloudFront is the global edge in front of public apps.

**2-minute explanation.** Ingress/ALB handles north-south traffic; Lattice handles east-west with IAM auth policies and no peering; CloudFront caches and terminates TLS at the edge (certificate in us-east-1) with the ALB as origin.

**5-minute deep explanation.** Ingress/ALB handles north-south traffic; Lattice handles east-west with IAM auth policies and no peering; CloudFront caches and terminates TLS at the edge (certificate in us-east-1) with the ALB as origin. When not to use each: single cluster does not need Lattice; dynamic APIs may not benefit from caching but still gain TLS/DDoS shielding.

**Architecture.** 31-vpc-lattice, 32-cloudfront, 29-alb.

**Troubleshooting question.** CloudFront 502/504: origin protocol, SG allowing CloudFront prefix list, host header.

**Production scenario.** Multi-account service mesh alternative: Lattice.

**Common mistakes.** Using Lattice for a handful of in-cluster services.

**Follow-up questions.** How does Lattice authorisation differ from NetworkPolicy?
