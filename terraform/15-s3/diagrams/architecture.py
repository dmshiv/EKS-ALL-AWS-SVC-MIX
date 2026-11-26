# Generates terraform/15-s3/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/15-s3/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.management import SystemsManagerParameterStore
from diagrams.aws.network import Endpoint
from diagrams.aws.security import IAMRole, KMS
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
    "15-s3 — product image bucket",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    tf = Terraform("15-s3\nbucket + policies\n+ SSM parameter")

    with Cluster("AWS account / VPC"):
        bucket = SimpleStorageServiceS3Bucket(
            "cloudcart-lab-product-images-<acct>-<region>\n"
            "versioning | SSE-KMS (bucket keys)\nblock public | BucketOwnerEnforced\n"
            "lifecycle: 30d noncurrent, 7d multipart\nbucket policy: TLS-only, our KMS key only"
        )
        kms = KMS("KMS data CMK (16-kms)\nSSE-KMS key")
        ssm = SystemsManagerParameterStore(
            "SSM parameter\n/cloudcart/lab/s3/bucket\napp reads at startup"
        )
        role = IAMRole(
            "roles from 08 / 09\nproduct-service: RW products/*\n+ KMS via S3 only\nIRSA demo: ListBucket only"
        )
        endpoint = Endpoint("S3 gateway endpoint\n(02-vpc-endpoints)\nprivate, free, no NAT")

    with Cluster("EKS cluster"):
        pod = Pod("product-service pod\n(Pod Identity creds)")

    tf >> Edge(label="1. creates bucket\n+ 5 protections") >> bucket
    tf >> Edge(label="2. attaches least-privilege\nidentity policies") >> role
    tf >> Edge(label="3. publishes\nbucket name") >> ssm
    bucket >> Edge(style="dashed", label="4. encrypted\nwith") >> kms
    pod >> Edge(style="dashed", label="5. assumes role\n(no keys)") >> role
    pod >> Edge(style="dashed", label="6. reads bucket name") >> ssm
    pod >> Edge(style="dashed", label="7. HTTPS\nPutObject/GetObject") >> endpoint
    endpoint >> Edge(style="dashed", label="8. object API\n(both gates must allow)") >> bucket

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
    diag.dot.edge(role.nodeid, "legend", style="invis")


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
