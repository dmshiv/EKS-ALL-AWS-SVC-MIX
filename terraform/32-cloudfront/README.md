# 32-cloudfront: global edge (optional)

## Objective
Put CloudFront in front of the ALB for edge TLS, caching of /static/*, DDoS absorption and an alias record.

## Architecture
```
user -> Route 53 -> CloudFront -> https origin.<domain> -> WAF/ALB -> pods
```

## AWS services and cost
No hourly fee; $0.085/GB egress after free tier + request fees.

## Prerequisites
Folders applied before this one: `26-route53`, `27-acm`. Apply order for the whole project: `scripts/execution-order.txt`. Needs `26-route53`, `27-acm`, a deployed Ingress, `enable_cloudfront=true`.

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `26-route53` | `dns_enabled`, `domain_name`, `zone_id`, `app_fqdn`, `origin_fqdn` |
| `27-acm` | `cloudfront_certificate_arn` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `enabled` | scripts / humans (verification, Helm values) |
| `distribution_id` | scripts / humans (verification, Helm values) |
| `distribution_domain` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/32-cloudfront/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- Distribution with two cache behaviors (dynamic = no cache, `/static/*` optimized), TLS 1.2+, alias A/AAAA records.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 32-cloudfront plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 32-cloudfront apply     # re-plans, asks you to type '32-cloudfront', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `curl -I https://cloudcart.<domain>/` | `x-cache` header and HTTP 200. |
| `curl -I https://cloudcart.<domain>/static/style.css (twice)` | Second response `Hit from cloudfront`. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **502/504**: Origin unreachable/slow or origin cert does not cover origin.<domain>.
- **Stale content**: Invalidate: `aws cloudfront create-invalidation`.
- **403**: WAF block or alias/cert mismatch.

## Cleanup
Safe to destroy. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 32-cloudfront destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 32-cloudfront'
```

## Lab vs production
Lock the ALB to CloudFront (managed prefix list or secret header), origin shield, WAF at the edge.

## Interview
**30 seconds:** CloudFront terminates TLS at the edge and caches static content; the ALB should accept only CloudFront traffic.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- Which requests do you cache?
- How do you stop users bypassing CloudFront?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
