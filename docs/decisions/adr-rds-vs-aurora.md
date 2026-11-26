# ADR: RDS vs Aurora

**Problem:** Choose the relational engine tier

**Options:** RDS PostgreSQL, Aurora PostgreSQL

**Decision:** RDS for the lab

**Reason:** Lower cost for small steady workloads

**Tradeoffs:** Aurora gives fast failover, up to 15 replicas, auto-growing storage

**Production considerations:** Choose Aurora for many replicas / <30s failover / large data
