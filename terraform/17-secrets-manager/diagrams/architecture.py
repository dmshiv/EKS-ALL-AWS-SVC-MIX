# Generates terraform/17-secrets-manager/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/17-secrets-manager/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EKS
from diagrams.aws.database import ElasticacheForRedis, RDSPostgresqlInstance
from diagrams.aws.management import SystemsManagerParameterStore
from diagrams.aws.security import IAMRole, KMS, SecretsManager
from diagrams.onprem.iac import Terraform

graph_attr = {
    "fontsize": "20",
    "bgcolor": "white",
    "pad": "0.4",
    "nodesep": "0.7",
    "ranksep": "1.0",
}

with Diagram(
    "17-secrets-manager — generated credentials in Secrets Manager",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    tf = Terraform(
        "17-secrets-manager\nrandom_password (state-only)\n+ 3 inline role policies\n+ 2 SSM ARN parameters"
    )

    with Cluster("AWS account"):
        kms = KMS("data CMK\n(from 16-kms)\nkms_key_id on both secrets")
        secrets = SecretsManager(
            "Secrets Manager\ncloudcart-lab/rds-credentials\ncloudcart-lab/redis-auth-token\nrecovery window 0 (lab)"
        )
        roles = IAMRole(
            "workload roles (08-pod-identity)\norder-svc + worker -> DB secret\nproduct-svc -> Redis token\nkms:Decrypt via secretsmanager only"
        )
        ssm = SystemsManagerParameterStore(
            "Parameter Store\n/cloudcart/lab/rds/secret_arn\n/cloudcart/lab/redis/secret_arn\n(ARNs only, not values)"
        )

    with Cluster("Terraform consumers (remote state)"):
        rds = RDSPostgresqlInstance("19-rds\ndb_username +\nrds_password (sensitive)")
        cache = ElasticacheForRedis("21-elasticache\nredis_auth_token\n(sensitive)")

    with Cluster("EKS cluster (runtime)"):
        pods = EKS("pods (Pod Identity)\nno K8s Secret, no env file\ncredentials in memory only")

    tf >> Edge(label="1. creates secrets\n+ versions (generated values)") >> secrets
    tf >> Edge(label="2. attaches least-privilege\nread policies") >> roles
    tf >> Edge(label="2b. publishes\nsecret ARNs") >> ssm
    secrets >> Edge(style="dashed", label="3. encrypted at rest") >> kms
    tf >> Edge(style="dashed", label="4. password/token via\nsensitive outputs") >> rds
    tf >> Edge(style="dashed", label="4b.", constraint="false") >> cache
    pods >> Edge(style="dashed", label="5. GetParametersByPath\n(learn the ARN)") >> ssm
    pods >> Edge(style="dashed", label="6. GetSecretValue\n(role: two gates)") >> secrets

    # Legend: solid arrows provision/configure AWS resources, dashed arrows move data.
    legend_label = (
        '<<TABLE BORDER="1" CELLBORDER="0" CELLSPACING="6" CELLPADDING="4">'
        '<TR><TD COLSPAN="2"><B>Legend</B></TD></TR>'
        '<TR><TD>&#8212;&#8212;&#9654;</TD><TD ALIGN="LEFT">creates / configures</TD></TR>'
        '<TR><TD>- - -&#9654;</TD><TD ALIGN="LEFT">reads / writes data</TD></TR>'
        "</TABLE>>"
    )
    diag.dot.node("legend", label=legend_label, shape="plaintext", fontsize="12")
    # Invisible edge anchors the legend near the bottom cluster instead of floating.
    diag.dot.edge(roles.nodeid, "legend", style="invis")


# -----------------------------------------------------------------------------
# Post-process: graphviz writes <image xlink:href="/abs/path/icon.png">, which
# breaks outside this machine. Inline every referenced PNG as a base64 data URI
# so the SVG is fully self-contained (renders in VS Code, GitHub, browsers).
# -----------------------------------------------------------------------------
import base64
import re

svg_path = os.path.join(HERE, "architecture.svg")
with open(svg_path, "r", encoding="utf-8") as fh:
    svg = fh.read()


def _embed(match):
    path = match.group(1)
    with open(path, "rb") as img:
        data = base64.b64encode(img.read()).decode("ascii")
    return f'xlink:href="data:image/png;base64,{data}"'


svg = re.sub(r'xlink:href="(/[^"]+\.png)"', _embed, svg)

with open(svg_path, "w", encoding="utf-8") as fh:
    fh.write(svg)

embedded = svg.count("base64")
print(f"architecture.svg written, {embedded} icons embedded")
