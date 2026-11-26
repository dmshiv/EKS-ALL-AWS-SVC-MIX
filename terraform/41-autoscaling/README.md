# 41-autoscaling: metrics-server and the autoscaler comparison

## Objective
Install metrics-server for the HPA and optionally the Cluster Autoscaler as a comparison.

## Architecture
```
load -> HPA adds pods -> Pending -> Karpenter (or CA) adds nodes -> scale down/consolidation
```

## AWS services and cost
Autoscalers free; nodes cost.

## Prerequisites
Folders applied before this one: `06-eks`. Apply order for the whole project: `scripts/execution-order.txt`. 

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `06-eks` | `cluster_name` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `metrics_server_addon` | scripts / humans (verification, Helm values) |
| `cluster_autoscaler_enabled` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/41-autoscaling/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- `aws_eks_addon.metrics_server`.
- Optional Cluster Autoscaler: Pod Identity role scoped by ASG tags + Helm release.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Kubernetes
`kubernetes/autoscaling/*.yaml` (HPAs, load test).

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 41-autoscaling plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 41-autoscaling apply     # re-plans, asks you to type '41-autoscaling', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `kubectl top nodes` | CPU/memory shown. |
| `kubectl -n cloudcart get hpa` | TARGETS show percentages, not <unknown>. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **HPA <unknown>**: metrics-server not Ready or pods lack CPU requests.

## Cleanup
Safe to destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 41-autoscaling destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 41-autoscaling'
```

## Lab vs production
Do not run CA and Karpenter on the same capacity; scale workers on queue depth (KEDA).

## Interview
**30 seconds:** HPA scales pods, Karpenter/CA scale nodes; requests drive both.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- Karpenter vs Cluster Autoscaler?
- Why is HPA <unknown>?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
