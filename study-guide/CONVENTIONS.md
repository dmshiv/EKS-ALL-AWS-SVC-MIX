# Study Guide Conventions (read fully before writing any page)

You are writing pages of a study guide for the CloudCart EKS project at
`/home/dom/K8-abhishek-veeramalla/EKS-ALL-AWS-SVC-MIX`. The reader is preparing
for interviews and wants to understand **what is actually happening, where, by
whom, and why** — in layman terms, but technically accurate.

## Ground rules

1. **Accuracy first.** For every terraform module, read its `README.md`
   completely and skim its `main.tf` (resources carry WHY/WHAT/DEPENDS ON
   comments). Never invent resource names, numbers, or wiring. Use the real
   inputs/outputs tables from the README. If the README and code disagree,
   trust the code and note it.
2. **Layman ≠ wrong.** Use an everyday analogy (pizza shop, post office,
   airport, apartment building...) then map every part of the analogy to real
   resources. Keep real names (e.g. `orders-dlq`, visibility timeout 60s).
3. Every page ends with its **diagram** (real AWS icons, PNG) — the image is
   the last content section before the source-links footer.
4. Do not duplicate the module README: complement it. Link to it.

## Page structure (follow exactly, in this order)

```markdown
# <folder> — <Catchy layman title> (<what it creates>)

> **One-liner:** one sentence, plain words.

## In plain English (the layman story)
<analogy with a bullet mapping analogy -> real resources; 1 short paragraph + bullets>

## What actually happens, step by step (who does what)
<numbered steps naming the actor: You -> scripts/tf.sh -> Terraform -> AWS service -> later at runtime: pod/kubelet/controller... Include real numbers: timeouts, retention, sizes, from the README/main.tf.>

## Key resources created
| Resource | What it is | Why it exists |
<3-8 rows>

## Wiring: who feeds this folder, who eats from it
- **Reads from:** <folders + which outputs> (from README "Inputs from previous folders")
- **Feeds:** <folders + which outputs> (from README "Outputs for later folders")
- **State:** own state file path pattern.

## Why this folder exists (and what breaks without it)
<the problem it solves; failure/cost/security consequence of skipping it; mention "Lab vs production" note if README has one>

## Interview corner
**30-second answer:** "<quotable paragraph>"
**Likely questions:** <3-5 Q with 1-2 sentence A each, from README Interview section + your own>
**Gotchas to mention:** <common mistakes, production notes>

## Diagram
![<slug> diagram](../diagrams/<slug>.png)
*One-line caption: what the colors/arrows mean.*

---

📎 **Source folder:** [terraform/<folder>/](../../terraform/<folder>/README.md) · **Apply:** `scripts/tf.sh <folder> plan` then `apply`
```

Pages go to `study-guide/terraform/<folder>.md` (e.g. `22-sqs.md`).
For non-terraform top-level folders pages go to `study-guide/<folder>.md` and
the diagram image path is `diagrams/<slug>.png`.

## Diagram rules

- One Python script per page at `study-guide/diagrams/src/<slug>.py` where
  `<slug>` equals the folder name (e.g. `22-sqs`, `application`, `helm`).
- Always start the script with:

```python
BASE = "/home/dom/K8-abhishek-veeramalla/EKS-ALL-AWS-SVC-MIX/study-guide/diagrams"
```

  and use `filename=f"{BASE}/<slug>"`, `show=False`, `direction="LR"`,
  `graph_attr={"fontsize": "20", "bgcolor": "white"}`.
- Use **official AWS icons** from the `diagrams` library:
  `from diagrams.aws.compute import EKS, EC2, Lambda, Fargate`;
  `diagrams.aws.network` (ELB, NLB, ALB, CloudFront, Route53, VPC, NATGateway,
  Endpoint, VPCLattice); `diagrams.aws.database` (RDS, Dynamodb, ElastiCache);
  `diagrams.aws.storage` (S3, EBS, EFS, Backup); `diagrams.aws.security`
  (KMS, SecretsManager, WAF, GuardDuty, SecurityHub, IAM, ACM);
  `diagrams.aws.integration` (SQS, SNS, EventBridge);
  `diagrams.aws.management` (Cloudwatch, Cloudtrail, Config, SystemsManager,
  AutoScaling); `diagrams.aws.containers` (ECR);
  `diagrams.aws.engagement`, `diagrams.aws.cost` (Budgets) etc.
  Check the exact class name by grepping the installed package:
  `ls ~/.local/lib/python3.12/site-packages/diagrams/aws/` and
  `python3 -c "import diagrams.aws.network as n; print([x for x in dir(n) if not x.startswith('_')])"`.
- Use `Cluster("...")` for the VPC / EKS cluster / subnets when it helps.
- Label edges with verbs (`SendMessage`, `pulls image`, `assume role`).
  Dashed edges (`Edge(style="dashed", ...)`) for encryption, telemetry,
  identity — not the main data path.
- 3–9 nodes max. This is a learning diagram, not the full architecture.
- Render with `cd /home/dom/K8-abhishek-veeramalla/EKS-ALL-AWS-SVC-MIX && python3 study-guide/diagrams/src/<slug>.py`
  and **verify the PNG exists** (`ls -la study-guide/diagrams/<slug>.png`).
  Fix import/typo errors until it renders. Do not mark a page done without its PNG.

## Exemplar

Read `study-guide/terraform/22-sqs.md` and `study-guide/diagrams/src/22-sqs.py`
before writing your first page. Match that tone and depth.
