# ADR: Why SQS?

**Problem:** Decouple slow order processing

**Options:** synchronous call, SQS, Kafka

**Decision:** SQS

**Reason:** Buffering, retries, DLQ, scales workers, no brokers to run

**Tradeoffs:** At-least-once, no ordering on standard queues

**Production considerations:** FIFO when ordering needed, alarms on age/DLQ
