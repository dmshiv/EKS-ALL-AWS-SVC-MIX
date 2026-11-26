# Generates terraform/02-vpc-endpoints/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/02-vpc-endpoints/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2ContainerRegistry
from diagrams.aws.database import Dynamodb
from diagrams.aws.network import Endpoint, Privatelink
from diagrams.aws.storage import SimpleStorageServiceS3
from diagrams.onprem.iac import Terraform

graph_attr = {
    "fontsize": "20",
    "bgcolor": "white",
    "pad": "0.4",
    "nodesep": "0.7",
    "ranksep": "1.0",
}

with Diagram(
    "02-vpc-endpoints — private paths to AWS services",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    vpc_state = Terraform(
        "01-vpc remote state\nvpc_id, vpc_cidr,\nprivate subnets + route tables"
    )
    tf = Terraform("terraform apply\n(scripts/tf.sh 02-vpc-endpoints)")

    with Cluster("VPC (private route tables / subnets from 01-vpc)"):
        s3_ep = Endpoint(
            "S3 gateway endpoint (FREE)\nroute to AWS prefix list\n(ECR image layers live in S3!)"
        )
        ddb_ep = Endpoint(
            "DynamoDB gateway endpoint (FREE)\nroute to AWS prefix list\n(product-service)"
        )
        iface_ep = Privatelink(
            "7 interface endpoints (optional, ~$51/month)\necr.api, ecr.dkr, sts, ssm,\nsecretsmanager, sqs, events\nPrivateLink ENI + private DNS, 1 AZ\nSG: tcp 443 from VPC CIDR"
        )

    s3 = SimpleStorageServiceS3("S3\n(objects + ECR layers)")
    ddb = Dynamodb("DynamoDB")
    aws_apis = EC2ContainerRegistry(
        "AWS service APIs\nECR, STS, SSM,\nSecrets Manager, SQS, EventBridge"
    )

    vpc_state >> Edge(style="dashed", label="1. reads\nterraform_remote_state") >> tf
    tf >> Edge(label="2. creates (free)") >> s3_ep
    tf >> Edge(label="2. creates (free)") >> ddb_ep
    tf >> Edge(label="3. creates if\nenable_interface_endpoints") >> iface_ep
    s3_ep >> Edge(label="4. traffic stays on\nAWS network, off NAT") >> s3
    ddb_ep >> Edge(label="4. traffic stays on\nAWS network, off NAT") >> ddb
    iface_ep >> Edge(label="4. sts.<region>.amazonaws.com\nresolves to private ENI IP") >> aws_apis

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
    diag.dot.edge(vpc_state.nodeid, "legend", style="invis")


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
