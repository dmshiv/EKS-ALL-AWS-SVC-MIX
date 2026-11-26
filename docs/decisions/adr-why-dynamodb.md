# ADR: Why DynamoDB?

**Problem:** Catalog lookups by key at low latency

**Options:** RDS table, DynamoDB, document DB

**Decision:** DynamoDB

**Reason:** Key-value access pattern, serverless scaling, IAM auth

**Tradeoffs:** Requires access-pattern modelling; limited ad hoc queries

**Production considerations:** Global tables, DAX, on-demand vs provisioned
