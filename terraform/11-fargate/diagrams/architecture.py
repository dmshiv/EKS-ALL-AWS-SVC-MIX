# Generates terraform/11-fargate/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/11-fargate/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EKS, Fargate
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
    "11-fargate — serverless pods for the fargate-demo namespace",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    tf = Terraform("tf.sh 11-fargate\n(terraform apply)")
    state = SimpleStorageServiceS3Bucket("Remote state (S3)\n01-vpc | 05-iam | 06-eks")
    pod = Pod("Pod in namespace\nfargate-demo\n(e.g. irsa-test)")

    with Cluster("AWS account — EKS cluster cloudcart-lab (06)"):
        eks = EKS("EKS control plane\nscheduler matches selectors")
        profile = Fargate(
            "Fargate profile demo\n"
            "selector: namespace=fargate-demo\n"
            "private subnets only"
        )
        microvm = Fargate(
            "One micro-VM per pod\n"
            "own ENI + cluster SG\nnode shows as fargate-ip-..."
        )
        exec_role = IAMRole(
            "Pod execution role (05-iam)\n"
            "pulls image from ECR, ships logs\n"
            "NOT the app identity (apps use IRSA)"
        )

    tf >> Edge(style="dashed", label="1. reads upstream outputs") >> state
    tf >> Edge(label="2. creates profile") >> profile
    profile >> Edge(label="3. registers with") >> eks
    pod >> Edge(style="dashed", label="4. matches selector\n(runtime)") >> profile
    profile >> Edge(label="5. EKS schedules\n(runtime)") >> microvm
    microvm >> Edge(style="dashed", label="6. runs as execution role") >> exec_role

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
    diag.dot.edge(pod.nodeid, "legend", style="invis")


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
