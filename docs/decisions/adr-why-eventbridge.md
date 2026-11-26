# ADR: Why EventBridge?

**Problem:** Route business events to reactions

**Options:** SNS only, EventBridge, direct calls

**Decision:** EventBridge for events, SNS for fan-out

**Reason:** Content-based routing, archive/replay, many targets

**Tradeoffs:** Higher per-event cost than SNS; eventual delivery

**Production considerations:** Schema registry, cross-account buses
