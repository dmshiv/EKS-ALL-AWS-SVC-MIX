# Generates terraform/09-irsa/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/09-irsa/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EKS
from diagrams.aws.security import (
    IdentityAndAccessManagementIam,
    IdentityAndAccessManagementIamAWSSts,
    IdentityAndAccessManagementIamRole,
)
from diagrams.aws.storage import SimpleStorageServiceS3Bucket
from diagrams.k8s.compute import Pod
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
    "09-irsa — IAM Roles for Service Accounts (OIDC web-identity)",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    with Cluster("Your machine"):
        you = User("You\n(developer)")
        tf = Terraform("09-irsa\nterraform apply\n(S3 backend via tf.sh)")

    eks = EKS("EKS cluster (06-eks)\nOIDC issuer URL\n+ registered OIDC provider")

    with Cluster("AWS account"):
        role = IdentityAndAccessManagementIamRole(
            "IAM role cloudcart-lab-irsa-demo\ntrust: Federated OIDC\n"
            "aud = sts.amazonaws.com\nsub = system:serviceaccount:<ns>:irsa-demo\n"
            "(ns: cloudcart, fargate-demo)"
        )
        sts = IdentityAndAccessManagementIamAWSSts("STS\nAssumeRoleWithWebIdentity\nverifies JWT vs OIDC provider\n+ aud/sub conditions")
        bucket = SimpleStorageServiceS3Bucket("15-s3 images bucket\n(ListBucket policy attached\nby 15-s3, not here)")

    with Cluster("Runtime (in the cluster)"):
        pod = Pod("Pod + SA irsa-demo\nannotated eks.amazonaws.com/role-arn\nworks on EC2 AND Fargate")

    you >> Edge(label="1. scripts/tf.sh\n09-irsa apply") >> tf
    tf >> Edge(style="dashed", label="2. reads 06-eks state\n(oidc_provider_arn, oidc_issuer)") >> eks
    tf >> Edge(label="3. creates role with\nconditioned trust") >> role
    bucket >> Edge(style="dashed", label="4. attaches ListBucket\npolicy to the role") >> role
    pod >> Edge(style="dashed", label="5. SDK sends\nprojected JWT") >> sts
    sts >> Edge(style="dashed", label="6. aud/sub match ->\ntemporary credentials") >> pod

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
