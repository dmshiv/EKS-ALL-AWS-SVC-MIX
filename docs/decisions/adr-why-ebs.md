# ADR: Why EBS?

**Problem:** Block storage for single-writer workloads

**Options:** EBS, EFS, instance store

**Decision:** EBS gp3 via CSI

**Reason:** Lowest latency, cheap

**Tradeoffs:** Single AZ, RWO

**Production considerations:** Snapshots/Backup; Retain for databases
