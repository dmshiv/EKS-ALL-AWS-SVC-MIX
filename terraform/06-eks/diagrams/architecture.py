# Generates terraform/06-eks/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/06-eks/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EKS
from diagrams.aws.management import CloudwatchLogs
from diagrams.aws.network import PrivateSubnet
from diagrams.aws.security import (
    IdentityAndAccessManagementIam,
    IdentityAndAccessManagementIamAddOn,
    IdentityAndAccessManagementIamRole,
    KeyManagementService,
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
    "06-eks — the managed Kubernetes control plane",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    with Cluster("Your machine"):
        you = User("You\n(developer)")
        tf = Terraform("06-eks\nterraform apply\n(S3 backend via tf.sh)")

    with Cluster("Upstream folders (remote state in S3)"):
        subnets = PrivateSubnet("01-vpc\nprivate_subnet_ids\n(control-plane ENIs live here)")
        role = IdentityAndAccessManagementIamRole("05-iam\ncluster_role_arn/name\n(identity of the control plane)")
        kms = KeyManagementService("16-kms\neks_secrets_key_arn\n(envelope-encrypts Secrets in etcd)")

    with Cluster("AWS account (this folder creates)"):
        eks = EKS(
            "EKS cluster cloudcart-lab\nk8s 1.35 | auth mode API\n"
            "private subnets | KMS-encrypted Secrets\noutputs read by 07-14, 26-47, 99"
        )
        logs = CloudwatchLogs("CloudWatch log group\n/aws/eks/cloudcart-lab/cluster\napi/audit/authenticator, 7-day retention")
        oidc = IdentityAndAccessManagementIam("IAM OIDC provider\nissuer = cluster URL\naud sts.amazonaws.com\n(consumed by 09-irsa)")
        addons = IdentityAndAccessManagementIamAddOn(
            "EKS add-ons\nvpc-cni (NetworkPolicy eBPF on)\nkube-proxy | pod-identity-agent"
        )

    you >> Edge(label="1. scripts/tf.sh 06-eks apply") >> tf
    tf >> Edge(style="dashed", label="2. reads remote state\n(subnets / role / key)") >> subnets
    tf >> Edge(style="dashed", label="2.") >> role
    tf >> Edge(style="dashed", label="2.") >> kms
    tf >> Edge(label="3. creates cluster\n(~10-15 min)") >> eks
    tf >> Edge(label="3b. pre-creates log group\n(else infinite retention)") >> logs
    eks >> Edge(style="dashed", label="4. issuer URL") >> oidc
    tf >> Edge(label="4. registers OIDC provider\n(basis of IRSA)") >> oidc
    tf >> Edge(label="5. installs 3 managed add-ons\n(no self-managed bootstrap)") >> addons

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
