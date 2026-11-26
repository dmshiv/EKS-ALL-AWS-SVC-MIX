# ADR: Why CloudFront?

**Problem:** Edge TLS, caching, DDoS absorption

**Options:** ALB only, CloudFront

**Decision:** CloudFront optional in front of ALB

**Reason:** Offloads static traffic, global edge, Shield Standard

**Tradeoffs:** Extra component and cache invalidation

**Production considerations:** Lock ALB to CloudFront
