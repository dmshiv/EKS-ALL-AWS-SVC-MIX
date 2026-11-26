# Generates terraform/10-node-groups/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/10-node-groups/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import AutoScaling, EC2, EKS
from diagrams.aws.security import IAMRole
from diagrams.aws.storage import SimpleStorageServiceS3Bucket
from diagrams.k8s.compute import Pod
from diagrams.onprem.iac import Terraform

graph_attr = {
    "fontsize": "20",
    "bgcolor": "white",
    "pad": "0.4",
    "nodesep": "0.7",
    "ranksep": "1.0",
}

with Diagram(
    "10-node-groups — EC2 system nodes (managed node group) + CoreDNS",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    tf = Terraform("tf.sh 10-node-groups\n(terraform apply)")
    state = SimpleStorageServiceS3Bucket(
        "Remote state (S3)\n01-vpc | 03-security-groups\n05-iam | 06-eks"
    )

    with Cluster("AWS account — EKS cluster cloudcart-lab (06)"):
        eks = EKS("EKS control plane\nauthentication_mode=API")
        lt = EC2(
            "Launch template system\n"
            "SGs: node-sg (03) + cluster SG (06)\n"
            "IMDSv2 required, hop limit 1\ngp3 30GiB encrypted root"
        )
        mng = AutoScaling(
            "Managed node group system\n"
            "t3.medium ON_DEMAND, min 2 / max 3\n"
            "AL2023 | max_unavailable=1\nlabel cloudcart.io/node-role=system"
        )
        coredns = Pod("CoreDNS add-on\n(cluster DNS)\nafter nodes exist")
        node_role = IAMRole("Node IAM role (05-iam)\nkubelet identity\n(EC2_LINUX access entry)")

    tf >> Edge(style="dashed", label="1. reads upstream outputs") >> state
    tf >> Edge(label="2. creates") >> lt
    tf >> Edge(label="3. creates MNG\n(uses launch template)") >> mng
    lt >> Edge(label="3b. settings") >> mng
    mng >> Edge(label="4. EKS-managed ASG\njoins cluster") >> eks
    mng >> Edge(style="dashed", label="5. kubelet authenticates\n(runtime)") >> node_role
    tf >> Edge(label="6. installs add-on\n(depends_on nodes)") >> coredns
    coredns >> Edge(style="dashed", label="runs on") >> mng

    # Legend: solid arrows provision/configure AWS resources, dashed arrows move data.
    legend_label = (
        '<<TABLE BORDER="1" CELLBORDER="0" CELLSPACING="6" CELLPADDING="4">'
        '<TR><TD COLSPAN="2"><B>Legend</B></TD></TR>'
        '<TR><TD>&#8212;&#8212;&#9654;</TD><TD ALIGN="LEFT">creates / configures</TD></TR>'
        '<TR><TD>- - -&#9654;</TD><TD ALIGN="LEFT">reads / identity / runtime</TD></TR>'
        "</TABLE>>"
    )
    diag.dot.node("legend", label=legend_label, shape="plaintext", fontsize="12")
    # Invisible edge anchors the legend near the bottom cluster instead of floating.
    diag.dot.edge(coredns.nodeid, "legend", style="invis")


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
