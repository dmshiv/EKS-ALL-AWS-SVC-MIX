# ADR: Why EFS?

**Problem:** Shared files across pods and AZs

**Options:** EFS, S3 + app logic

**Decision:** EFS with access points

**Reason:** RWX, multi-AZ, POSIX

**Tradeoffs:** Higher cost and latency

**Production considerations:** Backup, IA tier, throughput modes
