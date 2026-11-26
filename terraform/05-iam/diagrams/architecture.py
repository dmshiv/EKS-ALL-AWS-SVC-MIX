# Generates terraform/05-iam/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/05-iam/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2, EKS, Fargate
from diagrams.aws.security import IAMRole, IdentityAndAccessManagementIamAWSSts
from diagrams.onprem.iac import Terraform

graph_attr = {
    "fontsize": "20",
    "bgcolor": "white",
    "pad": "0.4",
    "nodesep": "0.7",
    "ranksep": "1.0",
}

with Diagram(
    "05-iam — service roles AWS itself assumes",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    tf = Terraform("terraform apply\n(scripts/tf.sh 05-iam)\nno upstream folder deps")

    with Cluster("AWS account — IAM (free, no long-lived credentials)"):
        cluster_role = IAMRole(
            "Cluster role\ntrusted by eks.amazonaws.com\nAmazonEKSClusterPolicy +\nAmazonEKSVPCResourceController"
        )
        node_role = IAMRole(
            "Node role\ntrusted by ec2.amazonaws.com\nWorkerNode + ECR-read-only +\nCNI + SSM (NO app permissions!)"
        )
        fargate_role = IAMRole(
            "Fargate pod execution role\ntrusted by eks-fargate-pods\n+ aws:SourceArn condition\n(confused-deputy protection)"
        )
        sts = IdentityAndAccessManagementIamAWSSts("STS\nvends temporary\ncredentials")

    with Cluster("Consumers (assume the roles at runtime)"):
        eks = EKS("06-eks\ncontrol plane")
        nodes = EC2("10-node-groups / 45\nkubelets + VPC CNI")
        fargate = Fargate("11-fargate\npod execution")

    tf >> Edge(label="1. creates 3 roles +\n7 policy attachments") >> cluster_role
    tf >> Edge(label="1. creates") >> node_role
    tf >> Edge(label="1. creates") >> fargate_role
    eks >> Edge(style="dashed", label="2. AssumeRole\n(manage ENIs/LBs)") >> cluster_role
    nodes >> Edge(style="dashed", label="3. AssumeRole\n(join cluster, pull ECR)") >> node_role
    fargate >> Edge(style="dashed", label="4. AssumeRole\n(pull image, ship logs)") >> fargate_role
    cluster_role >> Edge(style="dashed", label="5. temp credentials") >> sts

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
    diag.dot.edge(sts.nodeid, "legend", style="invis")


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
