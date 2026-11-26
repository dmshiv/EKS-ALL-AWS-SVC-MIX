# Cost (approximate; verify with the AWS Pricing Calculator)

| Item | Cost | Verdict |
|---|---|---|
| EKS control plane | ~$0.10/h (~$73/mo) | expensive-ish |
| NAT gateway | ~$0.045/h + $0.045/GB | expensive; 1 in the lab |
| EC2 nodes (2 x t3.medium) | ~$60/mo | expensive-ish |
| ALB / NLB | ~$16/mo each + LCU | expensive to forget |
| Interface endpoints | ~$7.3/mo per endpoint per AZ | expensive-ish |
| RDS db.t4g.micro | ~$12/mo | 24/7 until deleted |
| ElastiCache t4g.micro | ~$12/mo | 24/7 until deleted |
| EFS | ~$0.30/GB-mo | grows with data |
| WAF | $5/ACL + $1/rule + requests | |
| Container Insights / logs | ~$0.50/GB ingested | can exceed node cost |
| Config / GuardDuty / Security Hub | usage based | off by default where noted |
| DynamoDB, SQS, SNS, Lambda, S3, ECR, KMS | cents | cheap |
| Elastic IPs | ~$3.65/mo each | even when idle |
Minimize: destroy after each session (`scripts/destroy-all.sh`), single NAT, Spot via Karpenter, short log retention, budget alarms (00-bootstrap), `scripts/cost-check.sh`.
Resources created outside Terraform (ALB, EBS volumes, Karpenter nodes, Route 53 records) are removed by the cleanup script FIRST.
