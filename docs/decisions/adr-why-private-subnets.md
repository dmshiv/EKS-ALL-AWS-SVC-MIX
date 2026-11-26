# ADR: Why private subnets?

**Problem:** Keep nodes, pods and data off the internet

**Options:** public nodes, private nodes

**Decision:** Private subnets, public only for LB/NAT

**Reason:** Smaller attack surface, controlled egress

**Tradeoffs:** NAT and endpoint cost

**Production considerations:** NAT per AZ, endpoints
