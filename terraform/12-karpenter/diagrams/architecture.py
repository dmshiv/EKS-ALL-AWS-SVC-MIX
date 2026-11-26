# Generates terraform/12-karpenter/diagrams/architecture.svg
# Uses official AWS Architecture Icons via the `diagrams` library.
# Re-run:  python3 terraform/12-karpenter/diagrams/architecture.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2
from diagrams.aws.integration import Eventbridge, SimpleQueueServiceSqs
from diagrams.aws.security import IAMRole
from diagrams.aws.storage import SimpleStorageServiceS3Bucket
from diagrams.k8s.compute import Deployment
from diagrams.onprem.iac import Terraform

graph_attr = {
    "fontsize": "20",
    "bgcolor": "white",
    "pad": "0.4",
    "nodesep": "0.7",
    "ranksep": "1.0",
}

with Diagram(
    "12-karpenter — just-in-time node provisioning (controller + AWS plumbing)",
    filename=os.path.join(HERE, "architecture"),
    show=False,
    direction="LR",
    outformat=["svg", "png"],
    graph_attr=graph_attr,
) as diag:
    tf = Terraform("tf.sh 12-karpenter\n(terraform + helm)")
    state = SimpleStorageServiceS3Bucket("Remote state (S3)\n06-eks")

    with Cluster("AWS account — EKS cluster cloudcart-lab"):
        node_role = IAMRole(
            "Node role + EC2_LINUX access entry\n"
            "WorkerNode | ECR read | CNI | SSM\n"
            "(new nodes' kubelet identity)"
        )
        controller_role = IAMRole(
            "Controller role (Pod Identity)\n"
            "tag-scoped EC2/Fleet, PassRole\nonly node role -> ec2"
        )
        events = Eventbridge(
            "5 EventBridge rules\n"
            "spot interruption | rebalance\nstate change | health | capacity res."
        )
        queue = SimpleQueueServiceSqs(
            "SQS interruption queue\nname = cluster name\nretention 300s, SSE"
        )
        controller = Deployment(
            "Karpenter controller (helm 1.14.1)\n"
            "kube-system, 1 replica\n"
            "pinned to system MNG (10)"
        )
        nodes = EC2(
            "Just-in-time EC2 nodes\n"
            "NodePool general (spot+od) / batch-spot\n"
            "EC2NodeClass from kubernetes/karpenter"
        )

    tf >> Edge(style="dashed", label="1. reads cluster state") >> state
    tf >> Edge(label="2. creates roles\n+ access entry") >> node_role
    tf >> Edge(label="2b. creates role +\npod identity assoc") >> controller_role
    tf >> Edge(label="3. creates queue") >> queue
    tf >> Edge(label="3b. creates rules") >> events
    events >> Edge(label="4. delivers events") >> queue
    tf >> Edge(label="5. helm install (after\nroles, queue, entry)") >> controller
    controller >> Edge(style="dashed", label="6. Pod Identity credentials") >> controller_role
    controller >> Edge(label="7. watches Pending pods ->\nec2:CreateFleet (runtime)") >> nodes
    node_role >> Edge(style="dashed", label="7b. instance profile") >> nodes
    queue >> Edge(style="dashed", label="8. interruption -> drain\nbefore 2-min deadline") >> controller

    # Legend: solid arrows provision/configure AWS resources, dashed arrows move data.
    legend_label = (
        '<<TABLE BORDER="1" CELLBORDER="0" CELLSPACING="6" CELLPADDING="4">'
        '<TR><TD COLSPAN="2"><B>Legend</B></TD></TR>'
        '<TR><TD>&#8212;&#8212;&#9654;</TD><TD ALIGN="LEFT">creates / configures</TD></TR>'
        '<TR><TD>- - -&#9654;</TD><TD ALIGN="LEFT">identity / events / data</TD></TR>'
        "</TABLE>>"
    )
    diag.dot.node("legend", label=legend_label, shape="plaintext", fontsize="12")
    # Invisible edge anchors the legend near the bottom cluster instead of floating.
    diag.dot.edge(events.nodeid, "legend", style="invis")


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
