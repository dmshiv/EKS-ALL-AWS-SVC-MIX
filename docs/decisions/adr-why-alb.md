# ADR: Why ALB?

**Problem:** Expose HTTP services

**Options:** NodePort, NLB, ALB, API gateway

**Decision:** ALB via the AWS Load Balancer Controller

**Reason:** L7 routing, WAF, TLS, target-type ip direct to pods

**Tradeoffs:** Hourly cost; HTTP only

**Production considerations:** NLB for non-HTTP/static IP, Gateway API future
