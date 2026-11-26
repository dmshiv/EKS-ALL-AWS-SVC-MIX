# Generates terraform/04-ecr/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/04-ecr/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2, EC2ContainerRegistry
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
    "04-ecr — private container registry",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    kms_state = Terraform("16-kms remote state\ndata_key_arn\n(applied right after 03!)")
    tf = Terraform("terraform apply\n(scripts/tf.sh 04-ecr)")

    with Cluster("AWS account"):
        ecr = EC2ContainerRegistry(
            "4 ECR repositories\ncloudcart-{frontend, product-service,\norder-service, worker}\nIMMUTABLE tags | KMS encrypted\nscan-on-push (free CVE scan)\nlifecycle: untagged >7d expire, keep last 30"
        )
        nodes = EC2(
            "EKS nodes (runtime)\nkubelet pulls with NODE IAM role\nimage layers come from S3\n(needs S3 gateway endpoint, 02)"
        )

    developer = User("developer / CI\n(scripts/build-push.sh)")
    downstream = Terraform("Consumers (remote state)\n46-cicd: repository_arns\n99-capstone: repository_urls")

    kms_state >> Edge(style="dashed", label="1. reads\ndata_key_arn") >> tf
    tf >> Edge(label="2. creates repos\n+ lifecycle policies") >> ecr
    developer >> Edge(style="dashed", label="3. docker push\n(tag re-push FAILS = immutable)") >> ecr
    nodes >> Edge(style="dashed", label="4. image pull\n(ecr.api/ecr.dkr/S3)") >> ecr
    downstream >> Edge(style="dashed", label="5. read repo URLs/ARNs\nvia terraform_remote_state") >> ecr

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
    diag.dot.edge(developer.nodeid, "legend", style="invis")


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
