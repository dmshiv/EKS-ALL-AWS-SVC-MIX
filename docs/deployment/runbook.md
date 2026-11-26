# Deployment runbook

Everything is run by you; nothing applies automatically. Order: `scripts/execution-order.txt`. Per folder:
`scripts/tf.sh <folder> plan` (review) -> `apply` (typed confirmation, then `scripts/verify.sh`).

## Image lifecycle
```
Application source -> Dockerfile -> docker build -> local image store -> tag <ecr>/<repo>:vX.Y.Z-<sha>
-> scan (trivy locally, ECR on push) -> aws ecr get-login-password | docker login -> docker push -> ECR (immutable tags)
-> Helm values imageTag -> kubelet pulls with the NODE role -> Pod
```
`scripts/build-push.sh`. Immutable tags: same bytes everywhere, exact rollbacks, auditability. `latest` is refused by the chart and the scripts.
If a pull fails: wrong tag/URL, node role lacks ECR read, or no route to ECR/S3.

## Application
1. Infra folders through 25 (+ 28 for ingress). 2. `scripts/deploy-karpenter.sh`. 3. `scripts/build-push.sh`. 4. `terraform/99-capstone` apply.
5. `IMAGE_TAG=<tag> scripts/deploy-app.sh`. 6. USER_GUIDE end-to-end test.
## Pipelines
Image pipeline: GitHub Actions (OIDC, folder 46) builds, scans, pushes. Deployment: `helm upgrade --atomic` or GitOps (folder 47). Rollback: `helm rollback` / `git revert`.
Terraform pipeline: plan on pull request, apply after approval, one folder per job in dependency order.
