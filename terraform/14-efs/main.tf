# =============================================================================
# 14-efs : shared file system (EFS) + EFS CSI driver
# =============================================================================
#
#   Pod(s) in ANY AZ --> PVC (ReadWriteMany) --> EFS CSI node plugin --> NFS v4.1 over tcp/2049
#       --> mount target ENI in the node's own AZ  [EFS security group: allow 2049 from node-sg (03)]
#       --> EFS file system (data replicated across AZs, encrypted with the CMK)
#
# EBS vs EFS vs S3
#                     EBS                      EFS                        S3
#   type              block (ext4/xfs)         shared POSIX filesystem    object store (HTTP API)
#   access mode       RWO (one node)           RWX (many nodes/AZs)       n/a (API)
#   scope             single AZ                regional (multi-AZ)        regional (11 9s)
#   latency           lowest (sub-ms)          ms (network FS)            10s of ms
#   price (approx.)   ~$0.08/GB-mo (gp3)       ~$0.30/GB-mo (+ IA tier)   ~$0.023/GB-mo
#   use for           databases, caches        shared uploads, CMS, ML    images, backups, data lakes
#
# COST WARNING: EFS bills per GB-month of stored data until it is deleted. Elastic throughput bills per GB transferred.
# PERFORMANCE: generalPurpose + elastic throughput suits spiky workloads; small-file/metadata-heavy workloads are slower than EBS.
# DEPENDS ON: 01-vpc, 03-security-groups, 06-eks, 16-kms, nodes (10).  CONSUMED BY: kubernetes/storage/efs-*.yaml.

# WHAT:   Managed NFS v4.1 file system, encrypted with the data CMK.
# lifecycle_policy: files untouched for 30 days move to the cheaper Infrequent-Access class automatically.
resource "aws_efs_file_system" "shared" {
  creation_token   = "${local.name}-shared"
  encrypted        = true
  kms_key_id       = local.data_key_arn
  performance_mode = "generalPurpose"
  throughput_mode  = var.efs_throughput_mode

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = { Name = "${local.name}-shared" }
}

# Automatic daily backups through AWS Backup (vault/plan view in 40-backup).
resource "aws_efs_backup_policy" "shared" {
  file_system_id = aws_efs_file_system.shared.id

  backup_policy {
    status = "ENABLED"
  }
}

# MOUNT TARGETS: the ENI-based NFS endpoints, one per AZ in the private subnets. A node mounts the target in ITS OWN AZ (no cross-AZ
# charge). Missing target in an AZ => nodes there cannot mount ("mount.nfs: Connection timed out").
resource "aws_efs_mount_target" "shared" {
  for_each = toset(local.private_subnet_ids)

  file_system_id  = aws_efs_file_system.shared.id
  subnet_id       = each.value
  security_groups = [local.efs_sg_id]
}

# ACCESS POINT: an application-specific entry into the file system. It forces a POSIX identity (uid/gid) and a root directory for
# everything done through it, so a pod running as ANY user effectively acts as uid 10001 inside /cloudcart-shared and cannot see
# the rest of the file system. This is how multi-tenant EFS isolation works.
resource "aws_efs_access_point" "shared" {
  file_system_id = aws_efs_file_system.shared.id

  posix_user {
    uid = var.efs_posix_uid
    gid = var.efs_posix_uid
  }

  root_directory {
    path = "/cloudcart-shared"

    creation_info {
      owner_uid   = var.efs_posix_uid
      owner_gid   = var.efs_posix_uid
      permissions = "0755"
    }
  }

  tags = { Name = "${local.name}-shared-ap" }
}

# EFS CSI DRIVER (add-on) + role. The controller creates/deletes access points when you use dynamic provisioning (efs-ap StorageClass).
data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# WHY:        The EFS CSI controller needs permission to manage access points.
# DEPENDS:    Trusted via Pod Identity; used by the EFS CSI add-on.
# GOES WRONG: Dynamic provisioning (PVC with efs-ap mode) fails with AccessDenied when this is wrong.
resource "aws_iam_role" "efs_csi" {
  name               = "${local.name}-efs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

# WHY:        AWS managed EFS CSI policy.
# DEPENDS:    Depends on the EFS CSI role.
# GOES WRONG: Same as above.
resource "aws_iam_role_policy_attachment" "efs_csi" {
  role       = aws_iam_role.efs_csi.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}

# WHY:        Installs the EFS CSI driver as a managed add-on so versions are kept compatible with the cluster.
# DEPENDS:    Depends on the cluster, nodes and the EFS CSI role.
# GOES WRONG: Installed before nodes exist -> add-on stays DEGRADED; kubectl -n kube-system get pods shows the driver Pending.
resource "aws_eks_addon" "efs_csi" {
  cluster_name                = local.cluster_name
  addon_name                  = "aws-efs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  pod_identity_association {
    role_arn        = aws_iam_role.efs_csi.arn
    service_account = "efs-csi-controller-sa"
  }

  depends_on = [aws_iam_role_policy_attachment.efs_csi, aws_efs_mount_target.shared]
}
