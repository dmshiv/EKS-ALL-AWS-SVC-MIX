# Generates terraform/01-vpc/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/01-vpc/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.network import InternetGateway, NATGateway, PrivateSubnet, PublicSubnet
from diagrams.onprem.iac import Terraform
from diagrams.onprem.network import Internet

graph_attr = {
    "fontsize": "20",
    "bgcolor": "white",
    "pad": "0.4",
    "nodesep": "0.7",
    "ranksep": "1.0",
}

with Diagram(
    "01-vpc — three-tier network foundation",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    tf = Terraform("terraform apply\n(scripts/tf.sh 01-vpc)\nstate -> S3 backend")

    internet = Internet("Internet")

    with Cluster("AWS VPC 10.0.0.0/16 (3 AZs)"):
        igw = InternetGateway("Internet Gateway\npublic subnets' way out")
        public = PublicSubnet(
            "Public subnets x3 /24\n251 IPs each, ALB/NLB + NAT only\ntag: kubernetes.io/role/elb=1"
        )
        nat = NATGateway(
            "NAT gateway (lab: 1)\n+ Elastic IP\n~$33/month + per-GB"
        )
        private = PrivateSubnet(
            "Private subnets x3 /20\n4091 IPs each, EKS nodes + Pod IPs\ntags: internal-elb=1, karpenter discovery"
        )
        database = PrivateSubnet(
            "Database subnets x3 /24\nRDS + ElastiCache\nroute table has NO default route (isolated)"
        )

    downstream = Terraform(
        "Later folders\n02-vpc-endpoints, 03-security-groups,\n06-eks, 19-rds, 21-elasticache ..."
    )

    tf >> Edge(label="1. creates VPC, subnets,\nroute tables") >> public
    tf >> Edge(label="1. creates") >> private
    tf >> Edge(label="1. creates") >> database
    public >> Edge(label="2. route 0.0.0.0/0") >> igw
    private >> Edge(label="3. route 0.0.0.0/0") >> nat
    nat >> Edge(label="4. source-NAT via EIP\n(inbound impossible)") >> igw
    igw >> Edge(label="5. only path\nto/from internet") >> internet
    (
        downstream
        >> Edge(style="dashed", label="6. read vpc_id / subnet ids\nvia terraform_remote_state")
        >> private
    )

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
    diag.dot.edge(downstream.nodeid, "legend", style="invis")


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
