# ADR: Why VPC endpoints?

**Problem:** Reach AWS APIs privately and cheaply

**Options:** NAT only, endpoints

**Decision:** Gateway (S3, DynamoDB) + interface for key services

**Reason:** Lower NAT cost, private path, policies

**Tradeoffs:** Interface endpoints bill per AZ-hour

**Production considerations:** All AZs, endpoint policies
