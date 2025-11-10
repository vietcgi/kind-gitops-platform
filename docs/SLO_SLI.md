# Service Level Objectives (SLOs) and Indicators (SLIs)

## Overview

This document defines Service Level Objectives (SLOs) and Service Level Indicators (SLIs) for the Kubernetes Platform Stack. These metrics establish reliability targets and help quantify platform quality.

---

## Definitions

Service Level Indicator (SLI): A measured metric of service performance
- Example: 99.5% of API requests complete within 100ms

Service Level Objective (SLO): A target value for an SLI
- Example: 99.5% availability (what we aim for)

Error Budget: How much downtime is allowed under the SLO
- Example: 99.5% = 21.6 minutes downtime per month

---

## Platform SLOs

### 1. Cluster Availability (Target: 99.5%)

Definition: Percentage of time cluster API is responding to requests

SLI Measurement:
```
(requests with status 200-299) / (total requests)
```

Alert Thresholds:
- Warning: < 99.0% (monthly: > 43 minutes downtime)
- Critical: < 99.5% (monthly: > 21.6 minutes downtime)

Error Budget:
- Monthly: 21.6 minutes
- Weekly: 5 minutes
- Daily: 40 seconds

Calculation:
```promql
sum(rate(apiserver_request_total{code=~"2.."}[5m]))
/
sum(rate(apiserver_request_total[5m]))
```

---

### 2. Application Health (Target: 99.0%)

Definition: Percentage of deployed applications in Healthy state

SLI Measurement:
```
(healthy applications) / (total applications)
```

Target: All 17 platform applications healthy, all custom applications healthy

Alert Thresholds:
- Warning: < 99.0% (1 unhealthy app)
- Critical: < 95.0% (2+ unhealthy apps)

Calculation:
```promql
count(argocd_app_info{health_status="Healthy"})
/
count(argocd_app_info)
```

---

### 3. Pod Availability (Target: 99.0%)

Definition: Percentage of pods in Running state

SLI Measurement:
```
(running pods) / (desired pods)
```

Target: No crash loops, no pending pods

Alert Thresholds:
- Warning: < 99.0%
- Critical: < 95.0%

Calculation:
```promql
count(kube_pod_status_phase{phase="Running"})
/
count(kube_pod_status_phase)
```

---

### 4. API Latency (Target: p99 < 500ms)

Definition: 99th percentile of API request latency

SLI Measurement:
```
histogram_quantile(0.99, apiserver_request_duration_seconds_bucket)
```

Target: < 500ms for 99% of requests

Alert Thresholds:
- Warning: p99 > 500ms
- Critical: p99 > 1000ms

---

### 5. Secrets Encryption (Target: 100%)

Definition: All secrets stored encrypted

SLI Measurement:
```
All secrets in etcd encrypted with Sealed Secrets or Vault
```

Target: Zero plaintext credentials in git or cluster

Alert: Any plaintext secret detected (manual check quarterly)

---

### 6. Certificate Validity (Target: 100%)

Definition: All TLS certificates valid and not expiring soon

SLI Measurement:
```
(certificates with > 7 days until expiration) / (total certificates)
```

Target: All certificates auto-renewed before expiration

Alert Thresholds:
- Warning: < 90 days until expiration
- Critical: < 7 days until expiration

---

### 7. Backup Success Rate (Target: 99.0%)

Definition: Percentage of scheduled backups completed successfully

SLI Measurement:
```
(successful backups) / (attempted backups)
```

Target: Daily backups complete and are restorable

Verification: Monthly restore test of latest backup

---

### 8. Storage Capacity (Target: < 80%)

Definition: PVC utilization remains below 80%

SLI Measurement:
```
kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes
```

Alert Thresholds:
- Warning: > 80%
- Critical: > 90%

---

## Error Budgets

For 99.5% SLO:
- Monthly: 21.6 minutes downtime
- Weekly: 5 minutes downtime
- Daily: 40 seconds downtime

Usage Example:
```
If cluster was down 10 minutes this month:
- Remaining budget: 11.6 minutes
- Can afford 1 more incident this month
- Should increase monitoring/alerting
```

---

## SLI Dashboard

Create Grafana dashboard showing:

1. Cluster Availability (target: 99.5%)
2. Application Health (target: 99.0%)
3. Pod Availability (target: 99.0%)
4. API Latency - p99 (target: < 500ms)
5. API Latency - p95 (target: < 200ms)
6. API Latency - p50 (target: < 50ms)
7. Error Rate (target: < 0.1%)
8. Pod Restart Rate (target: 0)
9. Certificate Status (all valid)
10. Backup Status (all successful)

Dashboard JSON:
- Import from: manifests/monitoring/slo-dashboard.json
- Or create in Grafana UI and export

---

## Monthly SLO Review

Every month:

1. Calculate actual SLI values
2. Compare against SLO targets
3. Analyze any breaches:
   - Root cause analysis
   - Impact assessment
   - Action items to prevent recurrence
4. Review error budget spend
5. Update documentation if SLOs change
6. Share report with stakeholders

---

## SLO Update Procedure

To adjust SLOs:

1. Analyze historical data (at least 3 months)
2. Align with business requirements
3. Update SLO values in this document
4. Update alert thresholds
5. Update Prometheus rules
6. Commit changes: `git commit -m "chore: update SLOs to ..."`
7. Communicate changes to team

---

## Error Budget Policy

When error budget is exceeded:

1. Post-incident review within 24 hours
2. Root cause analysis
3. Corrective actions defined
4. Timeline for fixes
5. Reduced deployment frequency if systemic issues
6. Status page updates for transparency

---

## References

- Google's SRE Book: https://sre.google/books/
- SLI/SLO Best Practices: https://www.atlassian.com/incident-management/sla-vs-slo
- Prometheus alerting: docs/RUNBOOKS.md
