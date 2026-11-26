# Generates terraform/03-security-groups/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/03-security-groups/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.general import GenericFirewall
from diagrams.onprem.iac import Terraform

graph_attr = {
    "fontsize": "20",
    "bgcolor": "white",
    "pad": "0.4",
    "nodesep": "0.7",
    "ranksep": "1.0",
}

with Diagram(
    "03-security-groups — firewalls created before the cluster",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    vpc_state = Terraform("01-vpc remote state\nvpc_id")
    tf = Terraform("terraform apply\n(scripts/tf.sh 03-security-groups)")

    with Cluster("VPC (from 01-vpc) — all rules reference SGs, never CIDRs"):
        node_sg = GenericFirewall(
            "Node SG (cloudcart-lab-nodes)\nevery worker node ENI\nself-ingress all + open egress\ntag: karpenter.sh/discovery\n(NO kubernetes.io/cluster tag — breaks LBC)"
        )
        rds_sg = GenericFirewall("RDS SG\ntcp 5432 (PostgreSQL)\nsource = node SG only")
        redis_sg = GenericFirewall("Redis SG\ntcp 6379\nsource = node SG only")
        efs_sg = GenericFirewall("EFS SG\ntcp 2049 (NFS)\nsource = node SG only")

    downstream = Terraform(
        "Consumers\n10-node-groups, 14-efs, 19-rds,\n21-elasticache, 43, 45 (remote state)\n12-karpenter (discovery tag)"
    )

    vpc_state >> Edge(style="dashed", label="1. reads\nterraform_remote_state") >> tf
    tf >> Edge(label="2. creates") >> node_sg
    tf >> Edge(label="3. creates") >> rds_sg
    tf >> Edge(label="3. creates") >> redis_sg
    tf >> Edge(label="3. creates") >> efs_sg
    node_sg >> Edge(label="4. SG-to-SG rule:\npods/nodes may open 5432") >> rds_sg
    node_sg >> Edge(label="4. 6379") >> redis_sg
    node_sg >> Edge(label="4. 2049") >> efs_sg
    downstream >> Edge(style="dashed", label="5. read SG ids\n/ discover by tag") >> node_sg

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
    diag.dot.edge(downstream.nodeid, "legend", style="invis")


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
