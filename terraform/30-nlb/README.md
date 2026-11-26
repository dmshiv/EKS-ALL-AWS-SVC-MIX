# 30-nlb: static IPs for the NLB

## Objective
Pre-allocate Elastic IPs so an NLB keeps stable addresses across rebuilds.

## Architecture
```
Service type=LoadBalancer (annotations) -> controller -> NLB with EIPs -> target group (pod IPs)
```

## AWS services and cost
NLB ~$16/month + NLCU; each EIP ~$3.65/month even idle.

## Prerequisites
Folders applied before this one: `01-vpc`. Apply order for the whole project: `scripts/execution-order.txt`. 

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `01-vpc` | `azs`, `public_subnet_ids`, `private_subnet_ids` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `eip_allocation_ids` | `99-capstone` |
| `public_ips` | scripts / humans (verification, Helm values) |
| `public_subnet_ids` | `99-capstone` |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/30-nlb/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- `aws_eip.nlb` per AZ; outputs formatted for the annotations.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Kubernetes
`kubernetes/ingress/nlb-service.yaml`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 30-nlb plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 30-nlb apply     # re-plans, asks you to type '30-nlb', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `kubectl -n cloudcart get svc order-service-nlb` | EXTERNAL-IP shows the NLB DNS. |
| `aws elbv2 describe-load-balancers --query 'LoadBalancers[?Type==`network`]'` | State active. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **EIP count mismatch error**: Number of EIPs must equal subnets in the annotation.

## Cleanup
Release EIPs; they bill while allocated. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 30-nlb destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 30-nlb'
```

## Lab vs production
Use NLB for non-HTTP or static-IP needs; terminate TLS on the NLB or the pod; restrict source ranges.

## Interview
**30 seconds:** NLB is layer 4 with static IPs and client IP preservation; ALB is layer 7 with WAF and routing.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- When NLB over ALB?
- Why preallocate EIPs?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
