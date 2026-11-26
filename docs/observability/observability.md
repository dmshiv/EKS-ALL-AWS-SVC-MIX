# Observability

Application -> logs (what happened) -> metrics (how it behaves) -> traces (where time went) -> CloudWatch.
- Control-plane logs (api, audit, authenticator) in `/aws/eks/<cluster>/cluster`.
- Container Insights (folder 35): pod/node metrics and container logs. Alarms and dashboard (folder 34).
- CloudTrail (36): AWS API audit. WAF logs (33): why a request was blocked. ALB access logs (29): per-request evidence.
- Traces: optional ADOT collector + X-Ray (not enabled by default; cost and effort noted in the interview guide).
## 5xx troubleshooting flow
ALB target health -> pod readiness/restarts -> app logs -> dependency (DynamoDB/RDS/Redis/SQS) -> IAM (CloudTrail AccessDenied) -> SG/NetworkPolicy -> recent deploy/rollback.
