# ADR: Why EKS?

**Problem:** Run containers with Kubernetes on AWS

**Options:** ECS/Fargate, self-managed Kubernetes, EKS

**Decision:** EKS

**Reason:** Managed control plane, standard Kubernetes API/tooling, deep AWS integrations (IAM, VPC CNI, ELB)

**Tradeoffs:** $73/month control plane; Kubernetes operational complexity

**Production considerations:** Private endpoint, version upgrade cadence, access entries
