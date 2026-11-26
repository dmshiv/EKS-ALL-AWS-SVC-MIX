# Generates terraform/08-pod-identity/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/08-pod-identity/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EKS
from diagrams.aws.security import (
    IdentityAndAccessManagementIamPermissions,
    IdentityAndAccessManagementIamRole,
)
from diagrams.k8s.compute import DaemonSet, Pod
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
    "08-pod-identity — IAM for Pods with EKS Pod Identity",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    with Cluster("Your machine"):
        you = User("You\n(developer)")
        tf = Terraform("08-pod-identity\nterraform apply\n(S3 backend via tf.sh)")

    eks = EKS("EKS cluster cloudcart-lab\n(06-eks: cluster_name)\nagent add-on installed there")

    with Cluster("AWS account (this folder creates)"):
        roles = IdentityAndAccessManagementIamRole(
            "3 IAM roles, ZERO permissions\nproduct-service | order-service | worker\n"
            "trust: pods.eks.amazonaws.com\nsts:AssumeRole + sts:TagSession"
        )
        assoc = IdentityAndAccessManagementIamPermissions(
            "3 Pod Identity associations\n(cluster, ns=cloudcart, ServiceAccount)\n-> role; no SA annotation needed"
        )

    with Cluster("Runtime (on the node / downstream)"):
        pod = Pod("Pod with SA\ncloudcart/<service>\n(frontend: NO role by design)")
        agent = DaemonSet("Pod Identity Agent\nDaemonSet, 169.254.170.23\n(from 06-eks add-on)")
        data_folders = Terraform(
            "Data folders attach permissions\n15-s3, 17-secrets, 18-ssm,\n20-dynamodb, 22-sqs, 24-eventbridge"
        )

    you >> Edge(label="1. scripts/tf.sh 08-pod-identity apply") >> tf
    tf >> Edge(style="dashed", label="2. reads 06-eks\nremote state") >> eks
    tf >> Edge(label="3. creates roles") >> roles
    tf >> Edge(label="4. creates associations\n(SA -> role mapping)") >> assoc
    data_folders >> Edge(style="dashed", label="5. attach least-privilege\npolicies to role_names") >> roles
    pod >> Edge(style="dashed", label="6. SDK credential request\n(AWS_CONTAINER_CREDENTIALS_FULL_URI)") >> agent
    agent >> Edge(style="dashed", label="7. eks-auth:AssumeRoleForPodIdentity\n(association lookup)") >> assoc
    agent >> Edge(style="dashed", label="8. returns session-tagged\ntemporary STS creds") >> pod

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
