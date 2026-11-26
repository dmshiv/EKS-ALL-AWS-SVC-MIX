# Troubleshooting

Method for every failure: SYMPTOM -> HYPOTHESIS -> DIAGNOSTIC COMMANDS -> EVIDENCE -> ROOT CAUSE -> FIX -> PREVENTION. Never apply a fix before you have evidence.

| Symptom | First hypotheses | Commands |
|---|---|---|
| ImagePullBackOff | wrong tag/URL; node role ECR; no route to ECR/S3 | `kubectl describe pod`; `aws ecr describe-images`; check 02 endpoints |
| CrashLoopBackOff | app error, missing config, no credentials | `kubectl logs --previous`; `kubectl describe pod` |
| OOMKilled | memory limit too low / leak | `kubectl describe pod` (Last State), raise limit |
| Pod Pending | insufficient CPU/memory, taints, AZ volume, no IPs | `kubectl describe pod` events; Karpenter logs |
| NoCredentialsError | missing Pod Identity association / wrong SA / agent down | `aws eks list-pod-identity-associations`; agent DaemonSet |
| AccessDenied | IAM policy, KMS, resource policy, wrong role | CloudTrail `lookup-events`; `aws iam simulate-principal-policy` |
| DB timeout | SG source, route, TLS, pool | `nc -vz host 5432` in a pod; SG rules |
| DNS failure | CoreDNS down, SG/NetworkPolicy blocks 53 | `kubectl -n kube-system get pods -l k8s-app=kube-dns`; `nslookup` |
| Ingress no ADDRESS | controller down/IAM, subnet tags | controller logs; subnet tags |
| ALB 503/502/504 | no healthy targets / pod closed / slow | target group health; pod readiness; ALB logs |
| EBS mount failure | KMS grant, AZ mismatch | `kubectl describe pod`; CSI logs |
| EFS mount failure | SG 2049, mount target missing | `mount.nfs` event text |
| Karpenter no node | no NodePool match, limits, NodeClass not Ready | Karpenter logs; `kubectl get nodeclaims` |
| Node NotReady | CNI, SG, API route | `kubectl describe node`; CNI logs |
| SQS worker idle | permissions, wrong queue, visibility | worker logs; queue attributes |
| Lambda not invoked | rule pattern / permission | rule metrics; `aws events test-event-pattern` |
| Cert pending | zone not delegated | `dig NS`; ACM validation records |
Each is exercised as a controlled failure in USER_GUIDE.txt section 30.
