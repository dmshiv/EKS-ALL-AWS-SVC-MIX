# Generates terraform/16-kms/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/16-kms/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EKS
from diagrams.aws.integration import SNS
from diagrams.aws.security import IAMRole, KMS
from diagrams.aws.storage import SimpleStorageServiceS3Bucket
from diagrams.onprem.iac import Terraform

graph_attr = {
    "fontsize": "20",
    "bgcolor": "white",
    "pad": "0.4",
    "nodesep": "0.7",
    "ranksep": "1.0",
}

with Diagram(
    "16-kms — customer-managed encryption keys",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    tf = Terraform("16-kms\ntwo CMKs + aliases\n(apply right after 03,\nbefore 04/06)")

    with Cluster("AWS account"):
        eks_key = KMS(
            "CMK eks-secrets\nalias/cloudcart-lab-eks-secrets\nrotation ON, 7-day delete window\nkey policy: delegate to IAM"
        )
        data_key = KMS(
            "CMK data\nalias/cloudcart-lab-data\nrotation ON, 7-day delete window\n+ service principals w/ aws:SourceAccount"
        )
        roles = IAMRole("IAM roles\nleast-privilege kms: grants\nlive here (key policy\ndelegates to IAM)")
        svc = SNS("service principals\nsns · sqs · events · cloudwatch\nGenerateDataKey*/Decrypt")

    with Cluster("Consumers (read ARNs via remote state)"):
        eks = EKS("06-eks\nenvelope-encrypts\nSecrets in etcd")
        data_svcs = SimpleStorageServiceS3Bucket(
            "data at rest\n04-ecr · 13-ebs · 14-efs · 15-s3\n17-secrets · 19-rds · 20-dynamodb\n21-elasticache · 22-sqs · 23-sns\n24/25/34/40"
        )

    tf >> Edge(label="1. creates eks-secrets key\n+ alias + rotation") >> eks_key
    tf >> Edge(label="2. creates data key\n+ alias + key policy") >> data_key
    eks >> Edge(style="dashed", label="3. Encrypt/Decrypt\n(cluster role policy)") >> eks_key
    data_svcs >> Edge(style="dashed", label="4. encrypt / decrypt\nat rest") >> data_key
    svc >> Edge(style="dashed", label="5. encrypt on behalf\n(anti confused-deputy)") >> data_key
    roles >> Edge(style="dashed", label="6. IAM grants key use\nper role") >> eks_key
    roles >> Edge(style="dashed", constraint="false", label="6b.") >> data_key

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
