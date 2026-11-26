# CloudCart documentation

| Folder | Read it to understand |
|---|---|
| [architecture/](architecture/overview.md) | the whole platform, Terraform dependency graph, state design |
| [networking/](networking/eks-networking.md) | VPC, VPC CNI, prefix delegation, IPv6, packet flows |
| [security/](security/security-model.md) | IAM vs RBAC vs NetworkPolicy vs Security Groups, hardening, governance services |
| [identity/](identity/workload-identity.md) | IAM, STS, Pod Identity, IRSA, access entries |
| [storage/](storage/ebs-efs-s3.md) | EBS vs EFS vs S3 and the CSI drivers |
| [databases/](databases/data-stores.md) | RDS, DynamoDB, ElastiCache |
| [messaging/](messaging/event-driven.md) | SQS, SNS, EventBridge, Lambda and when to use which |
| [scaling/](scaling/scaling.md) | HPA, Karpenter, Cluster Autoscaler, Spot, Fargate |
| [observability/](observability/observability.md) | logs, metrics, traces, alarms |
| [troubleshooting/](troubleshooting/playbooks.md) | the symptom -> hypothesis -> evidence -> root cause -> fix method and 15 playbooks |
| [disaster-recovery/](disaster-recovery/dr.md) | backups, RTO/RPO, "the cluster is lost" drill |
| [cost/](cost/cost.md) | what costs money, how to minimize it, cleanup |
| [deployment/](deployment/runbook.md) | exact order, image lifecycle, CI/CD and GitOps |
| [interviews/](interviews/questions.md) | questions and 30s / 2min / 5min answers |
| [decisions/](decisions/README.md) | architecture decision records (why EKS, Pod Identity, ...) |
