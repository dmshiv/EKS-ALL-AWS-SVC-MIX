# 26-route53: DNS and ExternalDNS (optional, needs a domain)

## Objective
Use or create a hosted zone and install ExternalDNS so Ingress hostnames become Route 53 records.

## Architecture
```
user -> Route 53 -> cloudcart.<domain> ALIAS CloudFront | origin.<domain> ALIAS ALB (ExternalDNS)
```

## AWS services and cost
Hosted zone $0.50/month; queries $0.40/M. Domain registration separate.

## Prerequisites
Folders applied before this one: `06-eks`. Apply order for the whole project: `scripts/execution-order.txt`. Set `domain_name` (envs/lab/26-route53.tfvars). Needs `06-eks`, nodes.

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `06-eks` | `cluster_name` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `dns_enabled` | `27-acm`, `32-cloudfront`, `99-capstone` |
| `domain_name` | `27-acm`, `32-cloudfront` |
| `zone_id` | `27-acm`, `32-cloudfront` |
| `app_fqdn` | `32-cloudfront`, `99-capstone` |
| `origin_fqdn` | `32-cloudfront`, `99-capstone` |
| `name_servers` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/26-route53/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- Hosted zone (new or looked up); ExternalDNS Pod Identity role limited to this zone; Helm release with `upsert-only` and a txt owner id.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 26-route53 plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 26-route53 apply     # re-plans, asks you to type '26-route53', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `aws route53 list-hosted-zones-by-name --dns-name <domain>` | Zone present. |
| `dig NS <domain> +short` | Matches the zone's name servers (delegation). |
| `kubectl -n kube-system logs deploy/external-dns` | Records created after the Ingress exists. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **Name does not resolve**: Zone not delegated at the registrar, or record points at a deleted ALB.
- **ExternalDNS AccessDenied**: Role lacks ChangeResourceRecordSets on the zone.

## Cleanup
Records and (if created) the zone are deleted; the domain registration is not. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 26-route53 destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 26-route53'
```

## Lab vs production
PRODUCTION: DNSSEC, health-check failover, split-horizon, low TTL during cutovers.

## Interview
**30 seconds:** Route 53 hosts the DNS. ALIAS records point at AWS resources without CNAME limits. ExternalDNS keeps records in sync with Ingresses.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- ALIAS vs CNAME?
- What breaks if delegation is wrong?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
