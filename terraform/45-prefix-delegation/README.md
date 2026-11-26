# 45-prefix-delegation: more pods per node

## Objective
Show the effect of VPC CNI prefix delegation with a node group configured with maxPods=110.

## Architecture
```
ENI slot gets a /28 prefix -> ipamd hands pod IPs -> ~110 pods on an m5.large
```

## AWS services and cost
One m5.large while enabled (~$70/month).

## Prerequisites
Folders applied before this one: `01-vpc`, `03-security-groups`, `05-iam`, `06-eks`. Apply order for the whole project: `scripts/execution-order.txt`. `vpc_cni_prefix_delegation=true` in 06-eks.

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `01-vpc` | `private_subnet_ids` |
| `03-security-groups` | `node_security_group_id` |
| `05-iam` | `node_role_arn` |
| `06-eks` | `cluster_name`, `cluster_security_group_id` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `node_group_name` | scripts / humans (verification, Helm values) |
| `max_pods` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/45-prefix-delegation/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- Launch template with nodeadm NodeConfig maxPods; tainted node group `prefix-delegation` (count-gated).

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Kubernetes
`kubernetes/prefix-delegation/pods-scale.yaml` (60 pods).

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 45-prefix-delegation plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 45-prefix-delegation apply     # re-plans, asks you to type '45-prefix-delegation', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `kubectl get node -l cloudcart.io/node-role=prefix-delegation -o jsonpath='{.items[0].status.allocatable.pods}'` | 110. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Still 29 pods**: Only one switch flipped (CNI vs kubelet maxPods), or old node not replaced.
- **InsufficientCidrBlocks**: Fragmented subnet: no contiguous /28.

## Cleanup
Terminates the node. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 45-prefix-delegation destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 45-prefix-delegation'
```

## Lab vs production
Combine with big subnets or IPv6; monitor prefix fragmentation.

## Interview
**30 seconds:** Prefix delegation assigns /28 blocks per ENI slot, multiplying pod density; kubelet maxPods must be raised too.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- What happens when IPs run out?
- Two switches for prefix delegation?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
