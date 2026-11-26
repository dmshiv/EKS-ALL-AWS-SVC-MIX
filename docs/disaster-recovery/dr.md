# Disaster recovery

RPO = acceptable data loss; RTO = acceptable downtime. CloudCart lab targets: RPO <= 5 min (RDS PITR), RTO ~ 1-2 hours (rebuild).
| Layer | Protection |
|---|---|
| Multi-AZ | 3 AZ subnets, spread constraints, Multi-AZ RDS in production |
| RDS | automated backups + PITR, AWS Backup, final snapshot |
| DynamoDB | PITR, optional global tables |
| S3 | versioning, optional cross-region replication |
| EFS | automatic backups, AWS Backup |
| EBS | snapshots |
| Config/state | Git + versioned state bucket; secrets re-creatable |
| Cross-region | AWS Backup copy to a DR vault (folder 40) |
## "The entire EKS cluster is lost"
1. Data stores survive (they are not in the cluster). 2. `scripts/tf.sh 06-eks apply` and dependent folders (10, 12, 13, 14, 28, 35). 3. `scripts/deploy-karpenter.sh`.
4. `scripts/deploy-app.sh` with the same immutable image tag (images are in ECR). 5. Verify end to end. Everything is declarative: the cluster is cattle.
## Drill
USER_GUIDE section 31: delete the Helm release and the node group, rebuild from Git, measure time (RTO) and check no orders were lost (RPO).
