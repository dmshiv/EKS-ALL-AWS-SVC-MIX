# 47-gitops: Argo CD (optional)

## Objective
Install Argo CD so Git is the source of truth and the cluster pulls changes.

## Architecture
```
git push -> repo (helm/cloudcart) <- Argo CD in cluster -> apply -> drift reverted (selfHeal)
```

## AWS services and cost
Runs on existing nodes.

## Prerequisites
Folders applied before this one: none. Apply order for the whole project: `scripts/execution-order.txt`. 

## Inputs from previous folders
None. This folder reads no other folder's state (it needs only the S3 backend from `00-bootstrap`).

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `argocd_enabled` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/47-gitops/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- `helm_release.argocd` (count-gated).

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 47-gitops plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 47-gitops apply     # re-plans, asks you to type '47-gitops', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `kubectl -n argocd get pods` | Running. |
| `kubectl -n argocd port-forward svc/argocd-server 8080:443` | UI reachable locally. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **OutOfSync loops**: Another tool (Helm/Terraform) manages the same objects.

## Cleanup
Safe to destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 47-gitops destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 47-gitops'
```

## Lab vs production
App-of-apps, SSO, RBAC, image updater, separate repos for infra and app.

## Interview
**30 seconds:** GitOps pulls desired state from Git and reconciles continuously: no cluster credentials in CI, drift is corrected, rollback is git revert.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- GitOps vs CI/CD push?
- Who owns which objects: Terraform or Argo?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
