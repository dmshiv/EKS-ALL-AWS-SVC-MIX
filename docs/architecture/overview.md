# Architecture overview

```
 Users -> Route 53 -> CloudFront -> WAF -> ALB (public subnets)
                                            |
  VPC (3 AZ)  private subnets: EKS nodes + pod IPs
     frontend -> product-service -> DynamoDB (gateway endpoint)
                       |-> S3 images (SSE-KMS)      |-> ElastiCache (isolated subnet)
              order-service -> RDS (isolated subnet, creds from Secrets Manager)
                       '-> SQS -> worker (Spot) -> EventBridge -> Lambda -> SNS -> subscribers
  Identity: ServiceAccount -> Pod Identity -> IAM role -> STS temporary credentials
  Config: SSM Parameter Store   Secrets: Secrets Manager   Keys: KMS
  Observe: CloudWatch, Container Insights   Govern: CloudTrail, GuardDuty, Security Hub, Config, Backup
```

The animated diagram is [architecture/cloudcart-architecture.svg](../../architecture/cloudcart-architecture.svg).

## Terraform ownership

Terraform owns AWS infrastructure and platform add-ons; Helm/kubectl own application workloads. Rule: if it has an AWS lifecycle or an IAM
blast radius it is Terraform; if it changes with every deploy it is Kubernetes.

## Dependency graph (apply order: `scripts/execution-order.txt`)

```
00 bootstrap
01 vpc -> 02 endpoints
03 security-groups -> 16 kms -> 04 ecr
05 iam -> 06 eks -> 07 access, 08 pod-identity, 09 irsa
06 -> 10 node-groups -> 11 fargate, 12 karpenter, 13 ebs, 14 efs
15 s3, 17 secrets, 18 parameter-store -> 19 rds, 20 dynamodb, 21 elasticache
22 sqs -> 23 sns -> 24 eventbridge -> 25 lambda
26 route53 -> 27 acm ; 28 lb-controller -> 29 alb, 30 nlb, 33 waf, 32 cloudfront
34 cloudwatch, 35 container-insights, 36..39 security services, 40 backup
41 autoscaling, 42 network-policies, 43 sg-for-pods, 44 ipv6, 45 prefix-delegation, 46 cicd, 47 gitops
99 capstone (reads everything)
```

Only exception to "folder number = apply order": **16-kms is applied right after 03**, because ECR, EKS, EBS, EFS and S3 encrypt with it.

## State design

One S3 object per folder: `<bucket>/<environment>/<folder>/terraform.tfstate`, native locking, versioned, encrypted. Later folders read earlier
outputs with `terraform_remote_state`. `scripts/check-wiring.py` verifies statically that every output read exists and the order is consistent.

## Who owns each permission

`08-pod-identity` creates roles and associations; the folder that owns a resource attaches the policy for it (15-s3, 17, 18, 20, 22, 24).
A role never references an ARN that does not exist yet.
