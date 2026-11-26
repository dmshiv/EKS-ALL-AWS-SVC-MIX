# Generates terraform/00-bootstrap/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/00-bootstrap/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.cost import Budgets
from diagrams.aws.security import IdentityAndAccessManagementIamAWSSts
from diagrams.aws.storage import SimpleStorageServiceS3Bucket
from diagrams.generic.storage import Storage
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
    "00-bootstrap — Terraform state bucket + cost guardrail",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    with Cluster("Your machine (run once, local state)"):
        you = User("You\n(developer)")
        tf_local = Terraform("terraform apply\nLOCAL state\n(no backend block)")
        state_file = Storage("terraform.tfstate\nlocal file, git-ignored\n(rebuildable: terraform import)")

    with Cluster("AWS account"):
        sts = IdentityAndAccessManagementIamAWSSts("STS\nGetCallerIdentity\n(account id)")
        bucket = SimpleStorageServiceS3Bucket(
            "S3 state bucket\ncloudcart-tfstate-<acct>-<region>\n"
            "versioning | AES256 | block public\nTLS-only policy | 90-day version expiry"
        )
        budget = Budgets("AWS Budgets (optional)\nlimit $100/month (default)\nalerts at 50/80/100% -> e-mail")

    with Cluster("Every other folder (01-vpc ... 99-capstone)"):
        tf_remote = Terraform("backend \"s3\" {}\n(partial config)\n+ use_lockfile=true")

    you >> Edge(label="1. scripts/tf.sh 00-bootstrap apply") >> tf_local
    tf_local >> Edge(style="dashed", label="2. writes local state") >> state_file
    tf_local >> Edge(style="dashed", label="3. data: account id\n(builds bucket name)") >> sts
    tf_local >> Edge(label="4. creates bucket\n+ 5 security configs") >> bucket
    tf_local >> Edge(label="4b. only if\nbudget_email set") >> budget
    (
        tf_remote
        >> Edge(label="5. remote state per folder:\nlab/<folder>/terraform.tfstate\n(S3 native lockfile)")
        >> bucket
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
    diag.dot.edge(tf_remote.nodeid, "legend", style="invis")


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
