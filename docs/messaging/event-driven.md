# Messaging and events

```
order-service -> SQS orders -> worker (retries, DLQ) -> RDS update -> EventBridge -> Lambda -> SNS -> SQS notifications / e-mail
```
| Service | Model | Use when |
|---|---|---|
| SQS | pull queue, one consumer group | work to be done, buffering, retries, scale workers |
| SNS | push pub/sub | tell many subscribers; pair each with its own SQS queue |
| EventBridge | content-based routing of events | many producers/consumers, rules/filters, replay, SaaS events |
| Lambda | short serverless function | glue code reacting to events, no pods to run |
Do not treat them as interchangeable: SQS is a command queue, SNS a broadcast, EventBridge a router, Lambda compute.

SQS details: visibility timeout (60s) must exceed processing time; at-least-once delivery => idempotent handlers; DLQ after 5 receives; long polling 20s;
scale workers on queue depth (KEDA) not CPU. Lambda: async invocation retries twice, then target DLQ; handlers idempotent.
