# 99-capstone: the integration point

## Objective
Read every layer's state, publish one consolidated Helm value set and assert integration with `check` blocks. Creates no AWS resources.

## Architecture
```
Route 53 -> CloudFront -> WAF -> ALB -> EKS(frontend, product, order, worker) -> DynamoDB/S3/RDS/Redis/SQS -> EventBridge -> Lambda -> SNS
```

## AWS services and cost
None.

## Prerequisites
Folders applied before this one: `01-vpc`, `04-ecr`, `06-eks`, `08-pod-identity`, `09-irsa`, `14-efs`, `18-parameter-store`, `25-lambda`, `26-route53`, `27-acm`, `29-alb`, `30-nlb`, `33-waf`. Apply order for the whole project: `scripts/execution-order.txt`. Apply it last, after the images are pushed.

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `01-vpc` | `vpc_cidr`, `public_subnet_ids` |
| `04-ecr` | `repository_urls`, `registry_url` |
| `06-eks` | `cluster_name` |
| `08-pod-identity` | `namespace` |
| `09-irsa` | `irsa_demo_role_arn` |
| `14-efs` | `efs_file_system_id`, `efs_access_point_id` |
| `18-parameter-store` | `ssm_prefix` |
| `25-lambda` | (state must exist) |
| `26-route53` | `dns_enabled`, `app_fqdn`, `origin_fqdn` |
| `27-acm` | `alb_certificate_arn` |
| `29-alb` | `access_logs_bucket` |
| `30-nlb` | `eip_allocation_ids`, `public_subnet_ids` |
| `33-waf` | `web_acl_arn` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `helm_values` | scripts / humans (verification, Helm values) |
| `architecture_summary` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/99-capstone/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- `terraform_remote_state` for the layers the app needs; `helm_values` output consumed by `scripts/deploy-app.sh`.
- `check` blocks: DNS needs a certificate; Pod Identity namespace equals chart namespace; four ECR repositories.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 99-capstone plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 99-capstone apply     # re-plans, asks you to type '99-capstone', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `terraform -chdir=terraform/99-capstone output -json helm_values | jq .global` | All fields populated (empty only for optional DNS/TLS). |
| `scripts/deploy-app.sh` | Helm release ready; then the USER_GUIDE end-to-end test. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Check warnings at plan**: A layer disagrees with another: read the message.

## Cleanup
Nothing to destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 99-capstone destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 99-capstone'
```

## Lab vs production
Promote the same chart with env-specific values; keep this folder per environment.

## Interview
**30 seconds:** The capstone is where the layers meet: one value set feeds the Helm chart and integration checks catch drift between layers.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- Walk me through the complete architecture.
- How do you design this for multi-environment?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
