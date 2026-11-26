# 42-network-policies: platform baseline for pod traffic

## Objective
Apply default-deny ingress in the application namespace; allow rules live with the app.

## Architecture
```
default-deny-ingress + allow rules (Helm/kubernetes) -> eBPF enforcement by the VPC CNI
```

## AWS services and cost
Free.

## Prerequisites
Folders applied before this one: none. Apply order for the whole project: `scripts/execution-order.txt`. Namespace must exist: `kubectl apply -f kubernetes/namespaces/`. Needs `vpc_cni_network_policy=true` (06-eks).

## Inputs from previous folders
None. This folder reads no other folder's state (it needs only the S3 backend from `00-bootstrap`).

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `baseline_policy` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/42-network-policies/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- Data lookup of the namespace (fails fast if missing) and `kubernetes_network_policy_v1.default_deny_ingress`.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Kubernetes
`kubernetes/network-policies/01-allow-ingress.yaml`, `10-egress-lockdown.yaml`, `99-break-frontend-egress.yaml`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 42-network-policies plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 42-network-policies apply     # re-plans, asks you to type '42-network-policies', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `kubectl -n cloudcart get networkpolicy` | Baseline plus allow policies. |
| `kubectl -n cloudcart exec deploy/load-test -- wget -T3 -qO- http://order-service:8080/health` | Times out (not allowed from load-test). |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Policies have no effect**: VPC CNI network policy not enabled.
- **Everything times out after default-deny**: Allow policies missing; ALB source is the VPC CIDR, not a pod label.

## Cleanup
Safe to destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 42-network-policies destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 42-network-policies'
```

## Lab vs production
Default deny both directions, per-service allow lists, policy tests in CI.

## Interview
**30 seconds:** NetworkPolicy filters pod-to-pod by labels and is enforced by the CNI. It is additive. Security groups, IAM and RBAC operate at other layers.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- NetworkPolicy vs security group?
- Why are policies ignored without enforcement?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
