# Identity

```
IAM (roles, policies) -> STS (issues temporary credentials) -> AWS API
Kubernetes ServiceAccount -> Pod Identity / IRSA -> IAM role -> STS credentials -> AWS API
```
IAM user = long-lived keys (never used). IAM role = identity assumed for temporary credentials. STS = the service that issues them.

## Pod Identity flow
Pod -> SDK finds `AWS_CONTAINER_CREDENTIALS_FULL_URI` (injected by the EKS webhook) -> Pod Identity Agent (169.254.170.23) -> EKS Auth
(`AssumeRoleForPodIdentity`) -> association (cluster, namespace, SA) -> role (trust `pods.eks.amazonaws.com`) -> credentials.

## IRSA flow
Projected JWT (aud sts.amazonaws.com, sub system:serviceaccount:ns:sa) -> `AssumeRoleWithWebIdentity` -> IAM validates against the cluster OIDC
provider and trust conditions -> credentials. Annotation on the SA is required.

## Pod Identity vs IRSA
| | Pod Identity | IRSA |
|---|---|---|
| Needs OIDC provider | no | yes |
| Trust policy | same for every cluster | contains cluster OIDC URL |
| Fargate / outside EKS-on-EC2 | no | yes |
| Mapping stored | EKS API (association) | SA annotation + trust policy |
| Session tags / ABAC | yes | limited |
Default to Pod Identity; use IRSA on Fargate or non-EKS clusters.

## Who can use the cluster (humans/CI)
IAM authenticates; EKS access entries map the principal to Kubernetes groups/policies; RBAC decides verbs. `API` authentication mode removes the aws-auth ConfigMap.
