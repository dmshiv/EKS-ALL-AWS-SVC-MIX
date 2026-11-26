# ADR: Why Pod Identity?

**Problem:** Give pods AWS permissions without static keys

**Options:** node role, access keys, IRSA, Pod Identity

**Decision:** Pod Identity by default, IRSA for Fargate

**Reason:** No OIDC provider, reusable trust policy, EKS API association, session tags

**Tradeoffs:** Not on Fargate/Windows; needs agent and recent SDK

**Production considerations:** Role per workload, ABAC with session tags
