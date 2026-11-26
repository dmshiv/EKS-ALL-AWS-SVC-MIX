# 43-security-groups-for-pods: per-pod security groups

## Objective
Create a pod-specific SG and let it reach RDS, enabling least-privilege DB access per workload.

## Architecture
```
pod (SecurityGroupPolicy) -> branch ENI [pods-db SG] -> rds SG allows pods-db SG
```

## AWS services and cost
Free; fewer pods per node.

## Prerequisites
Folders applied before this one: `01-vpc`, `03-security-groups`, `06-eks`. Apply order for the whole project: `scripts/execution-order.txt`. Needs `vpc_cni_pod_eni=true` (06-eks) and a supported instance type (not t3).

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `01-vpc` | `vpc_id` |
| `03-security-groups` | `rds_security_group_id` |
| `06-eks` | `cluster_security_group_id` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `pods_db_security_group_id` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/43-security-groups-for-pods/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- Pods SG + rules; extra rule on the cluster SG for DNS; RDS ingress from the pod SG.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Kubernetes
`kubernetes/security-groups-for-pods/securitygrouppolicy.yaml`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 43-security-groups-for-pods plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 43-security-groups-for-pods apply     # re-plans, asks you to type '43-security-groups-for-pods', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `kubectl -n cloudcart get securitygrouppolicy` | Policy exists. |
| `kubectl -n cloudcart describe pod <order pod>` | Annotation vpc.amazonaws.com/pod-eni with a branch ENI. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Pod ContainerCreating: branch ENI**: Unsupported instance type or trunking not enabled.
- **DNS fails in pod**: Cluster SG rule from the pod SG missing.

## Cleanup
Safe to destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 43-security-groups-for-pods destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 43-security-groups-for-pods'
```

## Lab vs production
Use when compliance demands per-workload DB access; otherwise NetworkPolicy + IAM.

## Interview
**30 seconds:** SGP gives selected pods their own ENI and SG so database access is restricted to them rather than to every pod on the node.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- When SGP over NetworkPolicy?
- Limits of SGP?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
