# Security model

## The four layers (where each operates)
| Layer | Question | Evaluated by | Granularity |
|---|---|---|---|
| AWS IAM | may you call this AWS API? | AWS | principal + action + resource |
| Kubernetes RBAC / access policies | may you call this Kubernetes API? | API server | user/group + verb + resource |
| NetworkPolicy | may pod A reach pod B? | node (CNI eBPF) | labels / CIDR / port |
| Security group | may this ENI accept this packet? | VPC | SG / CIDR / port |
They stack. A NetworkPolicy cannot stop S3 access (IAM does); IAM cannot stop a pod reaching a DB port (SG/NetworkPolicy do).

## Controls implemented
- No static credentials: Pod Identity / IRSA temporary credentials; node IMDSv2 hop limit 1 so pods cannot steal the node role.
- Least privilege: one role per workload, policies attached by the resource owner, KMS use constrained with `kms:ViaService`.
- Network: private subnets, isolated DB subnets, SG references, default-deny NetworkPolicy, optional SG for pods, VPC endpoints.
- Data: KMS CMKs, TLS enforced (RDS force_ssl, S3 deny non-TLS, Redis TLS), versioning, backups.
- Secrets: Secrets Manager + SSM, none in Git/Kubernetes Secrets.
- Containers: non-root, read-only root filesystem, dropped capabilities, seccomp RuntimeDefault, PSA labels, immutable image tags, scan on push.
- Access: EKS access entries (API mode), namespace-scoped developer role, read-only role.

## Governance services (what each answers)
CloudTrail: who called which AWS API. EKS audit log: who called the Kubernetes API. GuardDuty: is something malicious. Config: how was it configured.
Security Hub: all findings in one place. WAF: layer-7 attacks at the ALB. None replaces the others; enable what you can triage.

## Enterprise additions (not in the lab)
Private-only API endpoint, SCPs and permission boundaries, separate accounts per environment, image signing, runtime security, central log archive.
