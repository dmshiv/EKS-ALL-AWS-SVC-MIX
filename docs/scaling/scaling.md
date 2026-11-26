# Scaling

Chain: load -> HPA adds pods -> pods Pending -> Karpenter provisions a node -> pods scheduled -> load falls -> HPA removes pods -> consolidation removes nodes.
- HPA: CPU utilization vs REQUESTS (needs metrics-server). Workers should scale on queue depth.
- Karpenter: pending pods -> NodePool requirements -> EC2NodeClass -> EC2 Fleet; Spot interruption via SQS; consolidation after 1 minute.
- Cluster Autoscaler: scales ASGs; slower, one shape per group. Do not run both on the same capacity.
- Managed node group: fixed system pool (Karpenter, CoreDNS, LB controller). Fargate: serverless pods for isolated demo workloads (IRSA only).
- Spot: stateless + idempotent only (worker); On-Demand for the rest; PDBs absorb drains.
Experiments: `kubernetes/karpenter/inflate.yaml`, `kubernetes/autoscaling/load-test.yaml`, `kubernetes/prefix-delegation/pods-scale.yaml` (USER_GUIDE section 32).
