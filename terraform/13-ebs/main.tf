# =============================================================================
# 13-ebs : EBS CSI driver (block storage for pods)
# =============================================================================
#
#   Pod --> PVC --> StorageClass gp3-encrypted (kubernetes/storage) --> EBS CSI controller (Pod Identity)
#       --> ec2:CreateVolume / AttachVolume --> EBS volume --> attached to ONE node --> mounted into the pod
#
# KUBERNETES OBJECTS: StorageClass = how to provision; PVC = a request ("10Gi RWO"); PV = the actual volume object the driver creates
# (dynamic provisioning); CSI = the plugin interface between Kubernetes and the storage provider.
# THE AZ RULE: an EBS volume lives in ONE Availability Zone and attaches to ONE node (ReadWriteOnce). If the pod reschedules into
# another AZ the volume cannot follow: it stays Pending with "volume node affinity conflict". WaitForFirstConsumer (in the StorageClass)
# creates the volume in the AZ where the pod is scheduled, which avoids the problem at creation time.
# SNAPSHOTS: EBS snapshots (regional, incremental) are the backup mechanism; Kubernetes VolumeSnapshot objects need the snapshot
# controller add-on (see docs/storage, and 40-backup for AWS Backup coverage).
#
# DEPENDS ON: 06-eks, 10-node-groups (the controller Deployment needs nodes), 16-kms.   CONSUMED BY: kubernetes/storage/*.yaml.
# COST: gp3 ~$0.08/GB-month. Volumes created by PVCs live OUTSIDE Terraform: delete PVCs BEFORE destroying the cluster or the
# volumes keep billing (scripts/destroy-all.sh does this).

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# WHY A ROLE: the controller pod calls EC2 APIs. It uses Pod Identity, so those rights belong to the controller ServiceAccount only.
resource "aws_iam_role" "ebs_csi" {
  name               = "${local.name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

# WHY:        The EBS CSI controller creates/attaches volumes using the AWS managed driver policy.
# DEPENDS:    Depends on the EBS CSI role; used by the EBS CSI add-on.
# GOES WRONG: Missing -> PVC stays Pending with 'UnauthorizedOperation'.
resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Volumes encrypted with OUR CMK: EC2 needs a KMS grant created on behalf of the volume. Without these statements the PVC is created
# but the pod stays ContainerCreating with "KMS key ... is not authorized" (a good failure-injection exercise, USER_GUIDE 12).
data "aws_iam_policy_document" "ebs_csi_kms" {
  statement {
    sid       = "ManageGrantsForAwsResources"
    actions   = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
    resources = [local.data_key_arn]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  statement {
    sid = "UseKey"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [local.data_key_arn]
  }
}

# WHY:        Encrypted volumes need the driver to use the data CMK (grants).
# DEPENDS:    Depends on the CSI role and 16-kms key.
# GOES WRONG: Missing -> PVC provisioning fails with 'KMS key does not exist or is not accessible'.
resource "aws_iam_role_policy" "ebs_csi_kms" {
  name   = "use-data-key"
  role   = aws_iam_role.ebs_csi.id
  policy = data.aws_iam_policy_document.ebs_csi_kms.json
}

# The add-on installs the controller Deployment + the node DaemonSet. pod_identity_association wires the controller ServiceAccount
# to the role, so no annotation or access key is involved.
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = local.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.ebs_csi_addon_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  pod_identity_association {
    role_arn        = aws_iam_role.ebs_csi.arn
    service_account = "ebs-csi-controller-sa"
  }

  depends_on = [aws_iam_role_policy.ebs_csi_kms, aws_iam_role_policy_attachment.ebs_csi]
}
