# Generates terraform/13-ebs/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/13-ebs/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EKS, EC2Instance
from diagrams.aws.security import IAMRole, KMS
from diagrams.aws.storage import EBS
from diagrams.k8s.compute import Pod
from diagrams.k8s.storage import PVC, StorageClass
from diagrams.onprem.iac import Terraform

graph_attr = {
    "fontsize": "20",
    "bgcolor": "white",
    "pad": "0.4",
    "nodesep": "0.7",
    "ranksep": "1.0",
}

with Diagram(
    "13-ebs — EBS CSI driver (block storage for pods)",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    tf = Terraform("13-ebs\naws_eks_addon +\nIAM role + KMS policy")

    with Cluster("AWS account"):
        role = IAMRole(
            "cloudcart-lab-ebs-csi\nPod Identity trust\nAmazonEBSCSIDriverPolicy\n+ KMS grants on data key"
        )
        kms = KMS("KMS data CMK (16-kms)\nencrypts every volume")
        vol = EBS(
            "EBS gp3 volume\nCMK-encrypted, ext4\nsingle AZ, RWO, one node\n~$0.08/GB-month"
        )

    with Cluster("EKS cluster (06-eks) + nodes (10-node-groups)"):
        csi = EKS("aws-ebs-csi-driver add-on\ncontroller + node DaemonSet\nSA: ebs-csi-controller-sa")
        pod = Pod("pod\n(deployed by app)")
        pvc = PVC("PVC\n\"10Gi RWO\"")
        sc = StorageClass(
            "StorageClass gp3-encrypted\n(kubernetes/storage, kubectl)\nWaitForFirstConsumer\nallowVolumeExpansion | Delete"
        )

    tf >> Edge(label="1. creates role +\npolicies") >> role
    tf >> Edge(label="2. installs add-on,\nwires Pod Identity") >> csi
    csi >> Edge(style="dashed", label="3. assumes role\n(no keys)") >> role
    csi >> Edge(style="dashed", label="4. CreateGrant /\nGenerateDataKey") >> kms
    pod >> Edge(label="5. mounts") >> pvc
    pvc >> Edge(label="6. requests via") >> sc
    sc >> Edge(label="7. provisions\n(after pod is scheduled)") >> csi
    csi >> Edge(label="8. ec2:CreateVolume\nin the pod's AZ") >> vol
    vol >> Edge(style="dashed", label="9. attached +\nmounted into pod") >> pod

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
