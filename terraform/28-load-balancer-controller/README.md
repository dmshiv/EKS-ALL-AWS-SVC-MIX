# 28-load-balancer-controller: AWS Load Balancer Controller

## Objective
Install the controller that turns Ingress into ALBs and LoadBalancer Services into NLBs, with Pod Identity.

## Architecture
```
Ingress/Service -> controller -> elasticloadbalancing API -> ALB/NLB -> target group (pod IPs)
```

## AWS services and cost
Controller free; every ALB/NLB ~$16/month + LCU. EXPENSIVE to forget.

## Prerequisites
Folders applied before this one: `01-vpc`, `06-eks`. Apply order for the whole project: `scripts/execution-order.txt`. Needs `01-vpc`, `06-eks`, nodes.

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `01-vpc` | `vpc_id` |
| `06-eks` | `cluster_name` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `controller_role_arn` | scripts / humans (verification, Helm values) |
| `helm_release_status` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/28-load-balancer-controller/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- Official IAM policy (`iam_policy.json`, pinned) on a Pod Identity role.
- Helm release with clusterName, region and vpcId set explicitly (pods cannot read IMDS).

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 28-load-balancer-controller plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 28-load-balancer-controller apply     # re-plans, asks you to type '28-load-balancer-controller', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `kubectl -n kube-system get deploy aws-load-balancer-controller` | Available. |
| `kubectl -n kube-system logs deploy/aws-load-balancer-controller` | No AccessDenied. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Ingress ADDRESS empty**: Controller not running, IAM denied, subnets lack kubernetes.io/role/elb tags, or no ingressClassName alb.
- **failed to get VPC ID**: vpcId not set (IMDS blocked).
- **webhook errors on Service creation**: Controller pods not ready yet.

## Cleanup
Delete Ingresses and LoadBalancer Services FIRST or ALBs/SGs are orphaned. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 28-load-balancer-controller destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 28-load-balancer-controller'
```

## Lab vs production
2+ replicas spread across AZs, pinned chart, WAF/Shield, deletion protection on ALBs.

## Interview
**30 seconds:** The controller is a pod that calls the ELB API. Target type ip sends traffic directly to pod IPs; ALB is L7, NLB is L4.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- target-type ip vs instance?
- ALB vs NLB?
- Why is Ingress ADDRESS empty?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
