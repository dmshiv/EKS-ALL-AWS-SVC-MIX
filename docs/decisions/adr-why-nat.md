# ADR: Why NAT?

**Problem:** Outbound internet from private subnets

**Options:** NAT gateway, NAT instance, endpoints only, IPv6 egress-only

**Decision:** One NAT in the lab

**Reason:** Simple and managed

**Tradeoffs:** Cost; single-AZ failure domain

**Production considerations:** NAT per AZ; endpoints reduce traffic
