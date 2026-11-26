# Generates terraform/18-parameter-store/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/18-parameter-store/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EKS
from diagrams.aws.management import SystemsManagerParameterStore
from diagrams.aws.security import IAMRole
from diagrams.onprem.iac import Terraform

graph_attr = {
    "fontsize": "20",
    "bgcolor": "white",
    "pad": "0.4",
    "nodesep": "0.7",
    "ranksep": "1.0",
}

with Diagram(
    "18-parameter-store — the application's configuration contract",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    tf = Terraform(
        "18-parameter-store\napp/* parameters\n+ read-ssm-config policy\non every workload role"
    )

    with Cluster("AWS account"):
        ssm = SystemsManagerParameterStore(
            "Parameter Store prefix\n/cloudcart/lab\nstandard tier, String only\n(secrets live in 17)"
        )
        roles = IAMRole(
            "workload roles (08-pod-identity)\nproduct-service · order-service · worker\nGetParameter(s)ByPath on\nprefix AND prefix/*"
        )

    with Cluster("Publisher folders (compute the same prefix locally)"):
        publishers = Terraform(
            "15-s3 · 17 · 19 · 20 · 21 · 22 · 23 · 24\nwrite s3/bucket, rds/host|port|dbname,\nredis/host|port, sqs url, table, topic, bus\n+ rds/secret_arn, redis/secret_arn"
        )

    with Cluster("EKS cluster (runtime)"):
        pods = EKS(
            "pods (Pod Identity)\nSSM_PREFIX env ->\nGetParametersByPath\nat startup (8 retries)"
        )

    capstone = Terraform("99-capstone\nreads ssm_prefix output\n-> Helm global.ssmPrefix")

    tf >> Edge(label="1. creates app/* params\n(log_level, cache_ttl)") >> ssm
    tf >> Edge(label="2. attaches read-only\nconfig policy") >> roles
    publishers >> Edge(style="dashed", label="3. publish endpoints\nunder the prefix") >> ssm
    pods >> Edge(style="dashed", label="4. reads whole prefix\n(WithDecryption)") >> ssm
    tf >> Edge(style="dashed", label="5. ssm_prefix via\nremote state") >> capstone

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
