# ADR: Why RDS?

**Problem:** Relational order data

**Options:** PostgreSQL in Kubernetes, RDS, Aurora

**Decision:** RDS PostgreSQL

**Reason:** Managed backups, patching, failover; simplest operations for steady load

**Tradeoffs:** Slower failover/replicas than Aurora

**Production considerations:** Multi-AZ, RDS Proxy, rotation
