# 46-cicd: GitHub Actions OIDC deploy role

## Objective
Let a pipeline push images to ECR and deploy to the cluster with short-lived OIDC credentials instead of access keys.

## Architecture
```
GitHub job -> OIDC token -> STS AssumeRoleWithWebIdentity -> role (push ECR + eks:DescribeCluster) -> access entry (edit in cloudcart)
```

## AWS services and cost
Free.

## Prerequisites
Folders applied before this one: `04-ecr`, `06-eks`. Apply order for the whole project: `scripts/execution-order.txt`. Set `github_repository` (OWNER/REPO). Needs `04-ecr`, `06-eks`.

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `04-ecr` | `repository_arns` |
| `06-eks` | `cluster_name`, `cluster_arn` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `deploy_role_arn` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/46-cicd/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- GitHub OIDC provider (or lookup), role trusted only for repo+branch, scoped ECR push policy, access entry + edit policy in the app namespace.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 46-cicd plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 46-cicd apply     # re-plans, asks you to type '46-cicd', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws iam get-role --role-name cloudcart-lab-github-deploy --query Role.AssumeRolePolicyDocument` | Subject limited to your repo/branch. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Not authorized to perform sts:AssumeRoleWithWebIdentity**: `sub` mismatch (repo/branch) or workflow lacks `permissions: id-token: write`.

## Cleanup
Safe to destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 46-cicd destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 46-cicd'
```

## Lab vs production
Environment-scoped roles, required reviewers, separate infra and app pipelines, signed images, rollback via git revert / helm rollback.

## Interview
**30 seconds:** CI authenticates with OIDC federation: no long-lived keys. The pipeline builds, scans, pushes immutable tags and deploys.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- Why OIDC for CI?
- Push vs pull deployment?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
