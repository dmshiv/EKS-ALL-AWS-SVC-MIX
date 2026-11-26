# ADR: Why Karpenter?

**Problem:** Fast, cost-aware node provisioning

**Options:** Cluster Autoscaler, Karpenter, EKS Auto Mode

**Decision:** Karpenter plus a small managed node group

**Reason:** Direct EC2 Fleet, instance diversity, consolidation, Spot interruption handling

**Tradeoffs:** More moving parts; AWS-specific

**Production considerations:** Pin AMIs, disruption budgets; consider EKS Auto Mode
