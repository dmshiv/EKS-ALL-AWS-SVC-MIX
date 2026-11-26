# Generates terraform/14-efs/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/14-efs/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EKS
from diagrams.aws.network import VPCElasticNetworkInterface
from diagrams.aws.security import IAMRole, KMS
from diagrams.aws.storage import EFS
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
    "14-efs — shared file system (EFS) + EFS CSI driver",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    tf = Terraform("14-efs\nEFS + mount targets\n+ access point + add-on")

    with Cluster("AWS account / VPC"):
        kms = KMS("KMS data CMK (16-kms)\nencrypts the file system")
        fs = EFS(
            "EFS cloudcart-lab-shared\nNFS v4.1, multi-AZ, CMK\nIA after 30 days\nAWS Backup: daily"
        )
        mt = VPCElasticNetworkInterface(
            "mount target ENIs\none per private subnet/AZ\nSG: tcp/2049 from node SG"
        )
        ap = EFS("access point\nroot /cloudcart-shared\nforces uid/gid 10001")
        role = IAMRole(
            "cloudcart-lab-efs-csi\nPod Identity trust\nAmazonEFSCSIDriverPolicy"
        )

    with Cluster("EKS cluster (06-eks) + nodes (10-node-groups)"):
        csi = EKS("aws-efs-csi-driver add-on\ncontroller + node DaemonSet\nSA: efs-csi-controller-sa")
        pods = Pod("pods in ANY AZ\nPVC ReadWriteMany\n(efs-ap StorageClass)")

    tf >> Edge(label="1. creates FS +\nmount targets + AP") >> fs
    tf >> Edge(label="2. creates role") >> role
    tf >> Edge(label="3. installs add-on,\nwires Pod Identity") >> csi
    fs >> Edge(style="dashed", label="4. encrypted\nwith") >> kms
    fs >> Edge(label="5. NFS endpoint\nper AZ") >> mt
    fs >> Edge(label="6. app entry point\n(isolation)") >> ap
    csi >> Edge(style="dashed", constraint="false", label="7. assumes role\n(manages access points)") >> role
    pods >> Edge(style="dashed", constraint="false", label="8. NFS tcp/2049\n(node mounts own AZ)") >> mt
    mt >> Edge(style="dashed", label="9. POSIX files") >> fs

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
