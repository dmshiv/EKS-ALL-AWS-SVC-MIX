# 35-container-insights: pod/node metrics and container logs

## Objective
Install the CloudWatch observability add-on (agent + Fluent Bit) with a Pod Identity role and controlled log retention.

## Architecture
```
pods stdout -> Fluent Bit -> /aws/containerinsights/<cluster>/application ; kubelet/cAdvisor -> agent -> ContainerInsights metrics
```

## AWS services and cost
Log ingestion ~$0.50/GB and per-observation metrics: can exceed node cost. EXPENSIVE if left on.

## Prerequisites
Folders applied before this one: `06-eks`. Apply order for the whole project: `scripts/execution-order.txt`. Needs `06-eks`, nodes.

## Inputs from previous folders
| From folder | Outputs read |
|---|---|
| `06-eks` | `cluster_name` |

## Outputs for later folders
| Output | Consumed by |
|---|---|
| `addon_name` | scripts / humans (verification, Helm values) |
| `log_group_prefix` | scripts / humans (verification, Helm values) |

## State location
`s3://cloudcart-tfstate-<account>-<region>/<environment>/35-container-insights/terraform.tfstate` (own state file, own lock).

## Terraform: what the important resources do
- Pre-created log groups with retention.
- Role with CloudWatchAgentServerPolicy via Pod Identity; `aws_eks_addon.observability`.

Every resource carries WHY / WHAT / DEPENDS ON / GOES WRONG comments in `main.tf`.

## Deployment (you run this; nothing is applied automatically)
```bash
source scripts/env.sh
scripts/tf.sh 35-container-insights plan      # checks upstream state exists, fmt, init, validate, plan -> REVIEW
scripts/tf.sh 35-container-insights apply     # re-plans, asks you to type '35-container-insights', applies, then runs scripts/verify.sh
```
`plan` reads AWS and shows the diff (success: a plan listing the resources above; failure: an auth, permission or upstream-state error). `apply` waits for AWS to finish: do not interrupt long operations.


## Verification
| Command | What it tells you |
|---|---|
| `kubectl -n amazon-cloudwatch get pods` | Agent and Fluent Bit Running. |
| `aws logs describe-log-groups --log-group-name-prefix /aws/containerinsights/cloudcart-lab` | Groups with data after a few minutes. |

## Troubleshooting (symptom, hypothesis, diagnostic, root cause, fix)
- **No data in CloudWatch**: Agent role/association missing: check pod logs for AccessDenied.
- **Bill spike**: Verbose app logs: lower level, filter, shorten retention.

## Cleanup
Log groups and their data are deleted. Destroy in reverse dependency order (`scripts/destroy-all.sh`), never before the folders that consume this one.
```bash
scripts/tf.sh 35-container-insights destroy   # prints a DESTRUCTIVE banner and asks for 'destroy 35-container-insights'
```

## Lab vs production
Sampling/filters, Prometheus + Grafana for high-cardinality metrics, ADOT for traces to X-Ray.

## Interview
**30 seconds:** Container Insights collects pod and node metrics and container logs into CloudWatch using an add-on and a Pod Identity role.

**2 minutes:** Walk through the architecture diagram above, then the identity flow, the network flow, one failure mode and its diagnosis.

**Questions**
- What does Container Insights cost drivers?
- How do you troubleshoot 5xx with these signals?

**Common mistakes:** Skipping verification, over-broad IAM, forgetting cleanup of resources created outside Terraform.
