# Generates terraform/07-eks-access/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/07-eks-access/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EKS
from diagrams.aws.security import (
    IdentityAndAccessManagementIamAWSSts,
    IdentityAndAccessManagementIamPermissions,
    IdentityAndAccessManagementIamRole,
)
from diagrams.onprem.client import User
from diagrams.onprem.iac import Terraform

graph_attr = {
    "fontsize": "20",
    "bgcolor": "white",
    "pad": "0.4",
    "nodesep": "0.7",
    "ranksep": "1.0",
}

with Diagram(
    "07-eks-access — who may use the Kubernetes API",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    with Cluster("Your machine"):
        you = User("You / CI\n(human principal)")
        tf = Terraform("07-eks-access\nterraform apply\n(S3 backend via tf.sh)")

    with Cluster("AWS account (this folder creates)"):
        roles = IdentityAndAccessManagementIamRole(
            "2 IAM roles\ncloudcart-lab-eks-readonly / -developer\n"
            "trust: account principals (sts:AssumeRole)\ninline: eks:DescribeCluster only"
        )
        entries = IdentityAndAccessManagementIamPermissions(
            "EKS access entries + policy associations\nreadonly: EKSViewPolicy, cluster-wide\n"
            "developer: EKSEditPolicy, ns=cloudcart\n(+ optional extra admins, var-gated)"
        )
        sts = IdentityAndAccessManagementIamAWSSts("STS\nAssumeRole\n(temporary credentials)")

    eks = EKS("EKS cluster cloudcart-lab\n(from 06-eks state:\ncluster_name, cluster_arn)\nauthentication_mode = API")

    you >> Edge(label="1. scripts/tf.sh 07-eks-access apply") >> tf
    tf >> Edge(style="dashed", label="2. reads 06-eks remote state") >> eks
    tf >> Edge(label="3. creates roles") >> roles
    tf >> Edge(label="4. maps roles into the cluster\n(replaces aws-auth ConfigMap)") >> entries
    entries >> Edge(label="4b. configures auth on") >> eks
    you >> Edge(style="dashed", label="5. runtime: assume role") >> sts
    sts >> Edge(style="dashed", label="6. eks get-token proves WHO;\nentry + policy decide WHAT") >> eks

    # Legend: solid arrows provision/configure AWS resources, dashed arrows move data.
    legend_label = (
        '<<TABLE BORDER="1" CELLBORDER="0" CELLSPACING="6" CELLPADDING="4">'
        '<TR><TD COLSPAN="2"><B>Legend</B></TD></TR>'
        '<TR><TD>&#8212;&#8212;&#9654;</TD><TD ALIGN="LEFT">creates / configures</TD></TR>'
        '<TR><TD>- - -&#9654;</TD><TD ALIGN="LEFT">reads / writes data / identity</TD></TR>'
        "</TABLE>>"
    )
    diag.dot.node("legend", label=legend_label, shape="plaintext", fontsize="12")
    # Invisible edge anchors the legend near the bottom cluster instead of floating.
    diag.dot.edge(tf.nodeid, "legend", style="invis")


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
