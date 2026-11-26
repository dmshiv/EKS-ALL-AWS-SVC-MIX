# Storage

| | EBS | EFS | S3 |
|---|---|---|---|
| Type | block | NFS filesystem | object API |
| Access mode | RWO, one node | RWX, many nodes/AZs | HTTP API |
| Scope | single AZ | regional | regional |
| Latency | lowest | ms | tens of ms |
| Cost | ~$0.08/GB-mo | ~$0.30/GB-mo | ~$0.023/GB-mo |
| Use | databases, caches | shared files | images, backups |

## EBS
Pod -> PVC -> StorageClass (gp3-encrypted, WaitForFirstConsumer) -> EBS CSI driver -> volume. AZ limitation: the volume stays in one AZ; a pod rescheduled elsewhere
gets `volume node affinity conflict`. Snapshots are regional and incremental; encryption with the data CMK needs KMS grants for the CSI role.

## EFS
Mount targets per AZ, security group allowing 2049 from nodes, access points force uid/gid and root directory. Cost is per GB stored until deleted.

## S3
Not a filesystem. Pods call the S3 API with Pod Identity credentials; SSE-KMS needs BOTH s3 and kms permissions; bucket policy denies non-TLS; versioning for recovery.
