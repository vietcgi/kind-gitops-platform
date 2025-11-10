# Disaster Recovery Plan

## Overview

This document outlines procedures for backing up and recovering from cluster failures. It includes RTO (Recovery Time Objective) and RPO (Recovery Point Objective) targets.

---

## Recovery Targets

RTO (Recovery Time Objective): Time to restore service
- Platform Services: 30 minutes
- Custom Applications: 1 hour
- Full Cluster: 2 hours

RPO (Recovery Point Objective): Data loss tolerance
- Configurations: 0 (every commit to git)
- Persistent Data: 24 hours (daily backups)
- Database Data: 24 hours (depends on backup schedule)

---

## What Gets Backed Up

### Automatically Backed Up

Via Velero:
- All Kubernetes manifests (applications, configs, CRDs)
- Persistent volumes (application data)
- Namespaces and RBAC policies
- ConfigMaps and Secrets (encrypted)
- Custom resources

Via Git:
- All Helm charts (helm/*)
- ApplicationSet definitions (argocd/*)
- Network policies (manifests/*)
- Infrastructure code
- History of all changes

### NOT Backed Up

These are transient or system-managed:
- Logs (see Loki retention policy)
- Temporary pods/jobs
- System namespace resources (kube-system, kube-public)
- Metrics (Prometheus data is 15 days, not persisted)

---

## Backup Procedures

### Pre-Backup Verification

Before backup run (daily):
```bash
# Check cluster health
kubectl get nodes
kubectl get applications -n argocd
kubectl get pvc -A

# Verify Velero is running
kubectl get pods -n velero
velero version

# List recent backups
velero backup get
```

### Automated Daily Backup

Velero runs backup daily at 2 AM UTC (see values.yaml):

```yaml
# argocd/applicationsets/platform-apps.yaml
schedules:
  daily-backup:
    schedule: "0 2 * * *"  # 2 AM daily
    template:
      includedNamespaces:
      - '*'
      excludedNamespaces:
      - kube-system
      - kube-public
      ttl: "720h"  # Keep 30 days
```

Monitor backups:
```bash
# List all backups
velero backup get

# Check specific backup
velero backup describe <backup-name>

# Watch current backup
velero backup logs <backup-name>

# Verify backup to storage
# Check S3/MinIO bucket for backup files
```

### Manual Backup

Create backup before maintenance:
```bash
# Create on-demand backup
velero backup create pre-maintenance-$(date +%Y%m%d) --wait

# Name format: <description>-<YYYYMMDD>
# Example: pre-upgrade-20251109

# Monitor creation
watch velero backup get

# Verify completion
velero backup describe pre-maintenance-20251109
```

### Storage Backend Configuration

Configure S3/MinIO for Velero (required for production):

```bash
# For AWS S3
kubectl create secret generic aws-credentials \
  --from-literal=cloud=<aws-access-key-id>:<aws-secret-access-key> \
  -n velero

# For MinIO (on-prem)
kubectl create secret generic minio-credentials \
  --from-literal=cloud=<minio-access-key>:<minio-secret-key> \
  -n velero

# Update Velero values:
# helm/velero/values.yaml
configuration:
  backupStorageLocation:
    provider: aws  # or s3 for MinIO
    bucket: velero-backups
    config:
      s3Url: https://s3.amazonaws.com  # or MinIO URL
      region: us-east-1
```

---

## Restore Procedures

### Scenario 1: Single Namespace Recovery

Restore a single namespace (e.g., app namespace was corrupted):

```bash
# List available backups
velero backup get

# Create restore from specific backup
velero restore create restore-app-ns-$(date +%Y%m%d) \
  --from-backup <backup-name> \
  --include-namespaces app \
  --wait

# Monitor restore
velero restore get
velero restore describe restore-app-ns-<date>

# Verify restoration
kubectl get pods -n app
kubectl get pvc -n app

# If needed, delete failed restore and try again
velero restore delete restore-app-ns-<date>
```

### Scenario 2: Full Cluster Recovery

Restore entire cluster from backup:

```bash
# List all backups (choose latest good one)
velero backup get

# Create full cluster restore
velero restore create restore-full-$(date +%Y%m%d) \
  --from-backup <latest-backup> \
  --wait

# Monitor restore (may take 30+ minutes)
velero restore get
velero restore logs restore-full-<date>

# Verify critical components
kubectl get nodes
kubectl get applications -n argocd  # Should show all 17 apps
kubectl get pods -A | grep -v Running  # Check for failures

# Verify ArgoCD state
argocd app list
argocd app sync --all --force  # Force resync all apps

# Verify secrets decrypted
kubectl get secret -A | wc -l  # Count secrets

# Check persistent data
kubectl get pvc -A
```

### Scenario 3: Point-in-Time Recovery

Restore cluster to specific point in time:

```bash
# Find backup nearest to desired time
velero backup get --show-labels

# Backups labeled with creation timestamp
# Example: 2025-11-09T02:00:00Z

# Restore from specific time's backup
velero restore create restore-pit-$(date +%Y%m%d) \
  --from-backup backup-<YYYY-MM-DD> \
  --wait

# Monitor and verify
velero restore describe restore-pit-<date>
kubectl get pods -A
```

### Scenario 4: Application-Only Recovery

Restore only custom applications (not platform):

```bash
# Create restore with namespace filter
velero restore create restore-apps-only-$(date +%Y%m%d) \
  --from-backup <backup-name> \
  --include-namespaces 'app,default' \
  --exclude-namespaces 'kube-*,velero' \
  --wait

# Verify application restoration
kubectl get pods -n app
kubectl get pvc -n app

# Resync with git
argocd app sync my-app
```

---

## Testing Restore Capability

Monthly restore test (critical!):

```bash
# 1. Schedule test day/time (non-production impact)

# 2. Create isolated test namespace
kubectl create namespace dr-test

# 3. Restore latest backup to test namespace
velero restore create dr-test-$(date +%Y%m%d) \
  --from-backup <latest-backup> \
  --namespace-mappings app:dr-test \
  --wait

# 4. Verify data integrity
kubectl get pods -n dr-test
kubectl get pvc -n dr-test
kubectl get secret -n dr-test | grep -v default-token

# 5. Test application functionality
# Run smoke tests
# Check data consistency

# 6. Document results
# Record: Success/failure, any issues
# Example: "Restore successful. All 5 app replicas started. Data intact."

# 7. Clean up test
kubectl delete namespace dr-test

# 8. Update restore test log
# File: docs/DISASTER_RECOVERY_LOG.txt
# Entry: "2025-11-09: DR test passed. Backup <name> verified good."
```

---

## Backup Validation Checklist

Monthly (at least):

```
- [ ] Latest backup exists and is recent (< 24 hours)
- [ ] Backup size is reasonable (compare with previous)
- [ ] Backup logs show no errors
- [ ] Velero pod is running and healthy
- [ ] Storage backend is accessible and has space
- [ ] All namespaces included in backup
- [ ] Persistent volumes included in backup
- [ ] Secrets are encrypted in backup
- [ ] Previous month's backup still exists (verify retention)
- [ ] Restore test completed successfully
```

---

## Failure Scenarios

### Backup Fails to Complete

Investigation:
```bash
# Check Velero logs
kubectl logs -n velero deployment/velero

# Check backup logs
velero backup logs <backup-name>

# Common issues:
# 1. Storage backend unreachable
#    -> Check credentials in Velero secret
#    -> Check network connectivity to S3/MinIO
# 2. Insufficient disk space
#    -> Check storage capacity
#    -> Delete old backups if needed
# 3. Permission issues
#    -> Verify IAM permissions
#    -> Check Velero RBAC
```

Resolution:
```bash
# Fix underlying issue

# Delete failed backup
velero backup delete <backup-name>

# Create new backup
velero backup create <backup-name> --wait
```

### Restore Hangs or Fails

Investigation:
```bash
# Check restore status
velero restore describe <restore-name>

# Check restores logs
velero restore logs <restore-name>

# Common issues:
# 1. PVC not provisioning
#    -> Check storage class
#    -> Check PVC size requests
# 2. Secrets/ConfigMaps not creating
#    -> Validate YAML syntax
#    -> Check namespace exists
# 3. Webhooks blocking resources
#    -> Check Kyverno/ValidatingWebhook
#    -> May need to disable temporarily
```

Resolution:
```bash
# Option 1: Delete and retry restore
velero restore delete <restore-name>
velero restore create <restore-name> --from-backup <backup> --wait

# Option 2: Partial restore (exclude problematic resources)
velero restore create <restore-name> \
  --from-backup <backup> \
  --exclude-resources secrets \
  --wait

# Then manually create secrets:
kubectl apply -f sealed-secrets.yaml
```

### Data Corruption After Restore

Investigation:
```bash
# Verify restore completed
velero restore describe <restore-name>

# Check application logs
kubectl logs -n app <pod-name>

# Verify data integrity
# Run application-specific health checks
```

Resolution:
```bash
# Use older backup
velero backup get --sort-by 'creationTimestamp'

# Identify last good backup (before corruption)
velero restore create <restore-name> \
  --from-backup <good-backup-name> \
  --wait

# Verify after restore
kubectl get pods -n app
# Run health checks
```

---

## RTO/RPO Achievement

Meeting RTO targets:

```
For 30-min RTO Platform Services:
- Have automated backups (Velero running 24/7)
- Test restore monthly to verify < 30 min restore time
- Document each test result
- Maintain < 24 hour RPO with daily backups

For 1-hour RTO Custom Apps:
- Include in Velero daily backup
- Store backup in accessible S3/MinIO
- Restore to isolated test namespace monthly

For 2-hour RTO Full Cluster:
- Use largest tested backup for time estimate
- Ensure storage backend has capacity
- Have network connectivity available
```

---

## Disaster Recovery Checklist

Pre-Disaster (Preventive):
```
- [ ] Backups enabled and running
- [ ] Storage backend configured and tested
- [ ] Restore test completed in past 30 days
- [ ] Team trained on restore procedures
- [ ] Documentation current and accessible
- [ ] RTO/RPO targets understood
```

During Disaster:
```
- [ ] Assess damage and impact
- [ ] Identify which data needs recovery
- [ ] Choose appropriate restore scenario
- [ ] Execute restore procedure
- [ ] Verify restored data integrity
- [ ] Communicate status to stakeholders
```

Post-Disaster (Recovery):
```
- [ ] Complete restore verification
- [ ] Document what happened (RCA)
- [ ] Identify prevention measures
- [ ] Update procedures based on lessons
- [ ] Test updated procedures
- [ ] Team debriefing and training
```

---

## Backup Storage Requirements

Minimum storage capacity:

```
Per 30-day retention:
- Cluster state: 1-5 GB
- Persistent volumes: (depends on data)
- Velero overhead: 10-20%

Example:
- 100 GB application data
- 30 daily backups
- Total: ~3.3 TB (100 * 30 + overhead)

Recommendation:
- Monthly: 200-500 GB
- Quarterly: 600 GB - 2 TB
- Annual: 2-5 TB (adjust for growth)
```

---

## Automation and Monitoring

Automated backup verification:

```bash
# Cron job to verify backups daily
0 3 * * * /usr/local/bin/check-backups.sh

# check-backups.sh
#!/bin/bash
LATEST=$(velero backup get --sort-by 'creationTimestamp' -o json | jq -r '.items[-1].metadata.name')
STATUS=$(velero backup describe $LATEST -o json | jq -r '.status.phase')

if [ "$STATUS" != "Completed" ]; then
  # Send alert
  curl -X POST https://hooks.slack.com/... -d "Backup failed: $LATEST"
  exit 1
fi
```

Monitoring dashboard:

Add to Grafana:
- Backup completion time (SLA: < 1 hour)
- Backup failure count
- Storage usage trend
- Last successful restore date

---

## Documentation and Change Control

Keep current:
- This file (update quarterly)
- Team training (annually)
- Restore test results (monthly log)
- RTO/RPO measurements (monthly)

Update triggers:
- Cluster topology changes
- Application volume size increases
- Backup retention policy changes
- Storage backend changes
- Disaster recovery incident

---

## Emergency Contacts

For severe disasters:

1. Incident Commander: [name + contact]
2. Database Admin: [name + contact]
3. Storage Admin: [name + contact]
4. Cloud Provider Support: [account number + support phone]

---

## References

- Velero Documentation: https://velero.io/docs/
- Kubernetes Backup Best Practices: https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/
- RTO/RPO Definition: https://en.wikipedia.org/wiki/Disaster_recovery#RTO_and_RPO

Last Updated: 2025-11-09
Tested: Monthly
