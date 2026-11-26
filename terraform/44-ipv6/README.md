# 44-ipv6: IPv6 design and a free dual-stack lab VPC

## Objective
Explain EKS IPv6 (immutable ip_family) and demonstrate dual-stack addressing and egress-only routing in a separate lab VPC.

## Architecture
```
private subnet --::/0--> egress-only IGW (no NAT) ; public --::/0--> IGW
```

## AWS services and cost
Free (no NAT, no instances).

## Prerequisites
Folders applied before this one: none. Apply order for the whole project: `scripts/execution-order.txt`. 

## Inputs from previous folders
None. This folder reads no other folder's state (it needs only the S3 backend from `00-bootstrap`).

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `lab_vpc_id` | scripts / humans (verification, Helm values) |
| `lab_ipv6_cidr` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/44-ipv6/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- Optional separate VPC with Amazon-provided IPv6, subnets, IGW, egress-only IGW, route tables.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 44-ipv6 plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 44-ipv6 apply     # re-plans, asks you to type '44-ipv6', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws ec2 describe-vpcs --vpc-ids <lab> --query 'Vpcs[0].Ipv6CidrBlockAssociationSet'` | A /56 associated. |
| `aws ec2 describe-route-tables ...` | private route ::/0 -> eigw-... |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Pod cannot reach an IPv4-only service in an IPv6 cluster**: Needs DNS64/NAT64.

## Cleanup
Safe to destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 44-ipv6 destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 44-ipv6'
```

## Lab vs production
IPv6 removes IP exhaustion; check dependencies for IPv4-only endpoints before adopting.

## Interview
**30 seconds:** IPv6 clusters give pods IPv6 only; no prefix delegation or secondary CIDR tricks needed; ip_family is immutable.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- Why choose IPv6 for EKS?
- Egress-only IGW vs NAT?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
