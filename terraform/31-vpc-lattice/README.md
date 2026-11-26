# 31-vpc-lattice: service-to-service networking (optional)

## Objective
Create a VPC Lattice service network and associate the VPC; services are added by the Gateway API controller.

## Architecture
```
pod -> Lattice service DNS -> service network -> target group; IAM auth policy per service
```

## AWS services and cost
Service network free; billed per service-hour and per GB/request. Disabled by default.

## Prerequisites
Folders applied before this one: `01-vpc`. Apply order for the whole project: `scripts/execution-order.txt`. 

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `01-vpc` | `vpc_id` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `service_network_id` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/31-vpc-lattice/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- `aws_vpclattice_service_network` and the VPC association (count-gated).

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 31-vpc-lattice plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 31-vpc-lattice apply     # re-plans, asks you to type '31-vpc-lattice', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws vpc-lattice list-service-networks` | The network exists when enabled. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Cannot reach a Lattice service**: VPC not associated, SG on the association blocks, or auth policy denies.

## Cleanup
Safe to destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 31-vpc-lattice destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 31-vpc-lattice'
```

## Lab vs production
Use for many teams/clusters/accounts; for one cluster a ClusterIP Service plus NetworkPolicy is simpler.

## Interview
**30 seconds:** Lattice is east-west application networking with IAM auth across VPCs and accounts; ALB/NLB are north-south.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- Lattice vs service mesh vs ClusterIP?
- When not to use Lattice?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
