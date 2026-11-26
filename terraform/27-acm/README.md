# 27-acm: TLS certificates (optional)

## Objective
Issue a validated wildcard certificate for the ALB (and a us-east-1 copy for CloudFront if needed).

## Architecture
```
ACM wildcard cert -> DNS validation CNAME in Route 53 -> ISSUED -> ALB listener / CloudFront
```

## AWS services and cost
ACM public certificates are free.

## Prerequisites
Folders applied before this one: `26-route53`. Apply order for the whole project: `scripts/execution-order.txt`. Needs `26-route53` with a domain.

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `26-route53` | `dns_enabled`, `domain_name`, `zone_id` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `alb_certificate_arn` | `99-capstone` |
| `cloudfront_certificate_arn` | `32-cloudfront` |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/27-acm/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- `aws_acm_certificate` DNS validation; validation records; `aws_acm_certificate_validation` blocks until ISSUED (no sleep).
- Second certificate in us-east-1 only when the stack runs elsewhere.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 27-acm plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 27-acm apply     # re-plans, asks you to type '27-acm', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws acm list-certificates --query 'CertificateSummaryList[].[DomainName,Status]'` | ISSUED. |
| `echo | openssl s_client -connect <host>:443 -servername <host>` | Verify return code 0 and the right subject. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Stuck Pending validation**: Zone not delegated or the CNAME missing.
- **CloudFront rejects certificate**: Wrong region: must be us-east-1.

## Cleanup
Safe to destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 27-acm destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 27-acm'
```

## Lab vs production
Keep validation CNAMEs forever (renewal depends on them); alarm on DaysToExpiry.

## Interview
**30 seconds:** ACM issues and renews certificates after DNS validation. TLS terminates at the ALB or CloudFront.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- Why us-east-1 for CloudFront?
- How does renewal work?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
