# ADR: Why ECR?

**Problem:** Private registry close to the cluster

**Options:** Docker Hub, GitHub Packages, ECR

**Decision:** ECR

**Reason:** IAM auth, same-region pulls via S3 endpoint, immutable tags, scan on push, lifecycle

**Tradeoffs:** AWS lock-in

**Production considerations:** Enhanced scanning, replication, pull-through cache, signing
