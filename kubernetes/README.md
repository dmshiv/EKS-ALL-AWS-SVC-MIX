# kubernetes/

Kubernetes objects for CloudCart and the labs. **Terraform owns AWS infrastructure and platform add-ons; this directory (and `helm/cloudcart`) owns workloads and scheduling policy.**

| Directory | Contents | Applied by |
|---|---|---|
| `namespaces/` | `cloudcart`, `fargate-demo` (with Pod Security labels) | `kubectl apply` (before 42-network-policies) |
| `serviceaccounts/` | one SA per service (names = Pod Identity associations), IRSA demo SAs | kubectl / Helm |
| `config/` | non-secret ConfigMap (SSM prefix, region) | kubectl / Helm |
| `secrets/` | intentionally empty: README explaining why | n/a |
| `frontend/ product-service/ order-service/ worker/` | Deployment, Service, PodDisruptionBudget | kubectl (raw) or Helm (same objects) |
| `ingress/` | ALB Ingress, NLB Service, Gateway API example | kubectl / Helm |
| `network-policies/` | allow rules, egress lockdown lab, deliberate failure | kubectl |
| `storage/` | StorageClasses, EBS/EFS demos, snapshot | kubectl |
| `autoscaling/` | HPAs, load test | kubectl / Helm |
| `karpenter/` | EC2NodeClass, NodePools, pending-pod experiment | `scripts/deploy-karpenter.sh` |
| `rbac/ fargate/ prefix-delegation/ security-groups-for-pods/` | labs | kubectl |

Files containing `${VARIABLES}` are templates: `scripts/render-k8s.sh` fills them from Terraform state into `.rendered/` (nothing is applied). The Helm chart (`helm/cloudcart`)
deploys the same application objects with values from `terraform/99-capstone`; use ONE path (Helm via `scripts/deploy-app.sh`) for the application, not both.
