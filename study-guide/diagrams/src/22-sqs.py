from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EKS
from diagrams.aws.integration import SQS
from diagrams.aws.security import KMS
from diagrams.aws.management import Cloudwatch

BASE = "/home/dom/K8-abhishek-veeramalla/EKS-ALL-AWS-SVC-MIX/study-guide/diagrams"

with Diagram(
    "22-sqs: orders queue + DLQ",
    show=False,
    direction="LR",
    filename=f"{BASE}/22-sqs",
    graph_attr={"fontsize": "20", "bgcolor": "white"},
):
    kms = KMS("KMS data key\n(from 16-kms)")

    with Cluster("EKS cluster"):
        order = EKS("order-service\n(producer)")
        worker = EKS("worker\n(consumer)")

    queue = SQS("orders queue\nvisibility 60s\nlong poll 20s")
    dlq = SQS("orders DLQ\n5 failed receives\n14d retention")
    cw = Cloudwatch("CloudWatch alarms\n(34-cloudwatch)")

    kms - Edge(style="dashed", label="encrypts") - queue
    order >> Edge(label="SendMessage") >> queue
    queue >> Edge(label="ReceiveMessage") >> worker
    queue >> Edge(label="redrive") >> dlq
    queue >> Edge(style="dashed", label="queue depth") >> cw
