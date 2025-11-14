# Incident Runbooks

## Overview

This document contains step-by-step procedures for responding to common incidents and alerts in the Kubernetes Platform Stack. Each runbook includes symptoms, investigation steps, and resolution procedures.

## Index

Pod Issues: Pod crash looping, OOM killer, unhealthy pods
Node Issues: Node not ready, memory/disk pressure
Storage Issues: PVC capacity, volume failures
Observability: Prometheus/Grafana failures, metric collection issues
GitOps: ArgoCD sync failures, application health
Certificates: Certificate expiration, renewal failures
Vault: Sealed vault, auth failures, TLS issues
Resource Management: Memory/CPU pressure, limits exceeded

---

## Pod Issues

### Pod Crash Looping

Alert: PodCrashLooping (Critical)

Symptoms:
- Alert fires when pod restarts more than 0.1 times per minute
- Pod repeatedly crashes and restarts
- Container status shows recent restarts

Investigation:
  kubectl describe pod <pod-name> -n <namespace>
  kubectl logs <pod-name> -n <namespace> --tail=100
  kubectl logs <pod-name> -n <namespace> --previous  # Previous container logs
  
Check for:
- OOM: Look for "OutOfMemory" in events or logs
- Exit code: Check container exit code (see exit code guide below)
- Resource limits: Verify resource limits aren't too low

Root Causes:
- Code bug: Application crashes immediately on startup
- Configuration: Missing/invalid environment variables
- Resource limits: Container killed due to memory or CPU limits
- Init container failure: Setup container failing

Resolution:

If configuration issue:
  kubectl set env deployment/<name> KEY=VALUE -n <namespace>
  kubectl rollout restart deployment/<name> -n <namespace>

If resource issue:
  # Check current usage
  kubectl top pod <pod-name> -n <namespace>
  
  # Update limits in values.yaml
  helm upgrade <release> helm/<chart> \
    --set resources.limits.memory=1Gi \
    -n <namespace>

If code issue:
  # Rollback to previous version
  kubectl rollout undo deployment/<name> -n <namespace>

Monitor recovery:
  watch kubectl get pods -n <namespace>
  kubectl logs -f <pod-name> -n <namespace>

---

### Container OOM Killer

Alert: ContainerOOMKiller (Critical)

Symptoms:
- Pod terminates with exit code 137 (0x89)
- Container status: OOMKilled
- Memory limit exceeded

Investigation:
  kubectl describe pod <pod-name> -n <namespace>
  # Look for: "Last State: Terminated, Reason: OOMKilled"
  
  kubectl top pod <pod-name> -n <namespace>  # Current memory
  
Check memory limit:
  kubectl get pod <pod-name> -n <namespace> -o yaml | grep memory

Root Causes:
- Application memory leak
- Memory limit too low for workload
- Spike in data processing

Resolution:

If memory leak (check logs for growing memory):
  # Restart pod to reset memory
  kubectl delete pod <pod-name> -n <namespace>
  
  # Fix code and redeploy
  git commit -m "fix: memory leak in <component>"
  git push

If limit too low:
  # Check actual memory usage pattern
  kubectl top pod <pod-name> -n <namespace>
  
  # Increase limit in Helm values
  # helm/<chart>/values.yaml
  resources:
    limits:
      memory: "2Gi"  # Increase from 1Gi
  
  # Apply upgrade
  helm upgrade <release> helm/<chart> -n <namespace>

Monitor:
  kubectl logs -f <pod-name> -n <namespace>
  watch kubectl top pod <pod-name> -n <namespace>

---

### Pod Not Healthy

Alert: PodNotHealthy (Critical)

Symptoms:
- Pod status: Pending, Unknown, or Failed
- Readiness probe failing
- Status message about scheduling/resources

Investigation:
  kubectl describe pod <pod-name> -n <namespace>
  # Check: Events, Conditions, Ready status
  
  kubectl get pod <pod-name> -n <namespace> -o yaml
  # Check: spec.containers[].livenessProbe, readinessProbe
  
Check logs:
  kubectl logs <pod-name> -n <namespace>
  kubectl logs <pod-name> -n <namespace> --previous

Check resource availability:
  kubectl describe nodes
  kubectl top nodes

Root Causes:
- Insufficient resources (no node with available resources)
- Image pull failure (image not available)
- Network policy blocking health checks
- Storage volume not available

Resolution:

If scheduling issue (Pending):
  # Check available resources
  kubectl describe nodes
  
  # See which node pod is waiting for
  kubectl describe pod <pod-name> -n <namespace>
  
  Options:
  a) Add more nodes to cluster
  b) Reduce resource requests if over-allocated
  c) Add node affinity to target specific nodes

If image pull failure:
  # Check image registry and auth
  kubectl describe pod <pod-name> -n <namespace>
  # Look for: ImagePullBackOff event
  
  # Verify image exists
  docker pull <image>
  
  # For KIND, load image locally
  kind load docker-image <image> --name platform
  
  # Restart pod
  kubectl delete pod <pod-name> -n <namespace>

If network policy blocking:
  # Test connectivity to health check endpoint
  kubectl run debug --image=busybox --rm -it --restart=Never -- \
    wget -O- http://<pod-ip>:8080/health
  
  # Check network policies
  kubectl get cnp -n <namespace>
  kubectl describe cnp <policy> -n <namespace>
  
  # Ensure policy allows health check port
  # See CONFIGURATION.md#network-policies

Monitor:
  watch kubectl get pods -n <namespace>
  kubectl logs -f <pod-name> -n <namespace>

---

## Node Issues

### Node Not Ready

Alert: NodeNotReady (Critical)

Symptoms:
- Node status: NotReady
- kubectl get nodes shows NotReady
- Pods cannot be scheduled

Investigation:
  kubectl describe node <node-name>
  # Check: Conditions, Status
  
  kubectl get nodes -o wide
  
SSH to node (if accessible):
  ssh -i <key> <node-user>@<node-ip>
  systemctl status kubelet
  journalctl -u kubelet -n 50

Root Causes:
- Kubelet crash or hung
- Node overloaded (memory/disk/CPU)
- Network issues preventing heartbeat
- Container runtime issues

Resolution:

If kubelet issue:
  # Restart kubelet
  ssh <node-ip> "sudo systemctl restart kubelet"
  
  # Monitor kubelet logs
  kubectl logs -n kube-system kubelet --tail=100

If node overloaded:
  # Check resource usage
  kubectl top node <node-name>
  
  # Cordon node to prevent new pods
  kubectl cordon <node-name>
  
  # Drain pods to other nodes
  kubectl drain <node-name> --ignore-daemonsets
  
  # Fix resource issue (clear disk, add memory, etc.)
  
  # Uncordon to resume
  kubectl uncordon <node-name>

If network issue:
  # Restart networking
  # This varies by CNI (Cilium, Flannel, etc.)
  kubectl -n kube-system rollout restart daemonset cilium

Wait for recovery:
  watch kubectl get nodes
  # Should show Ready status

---

### Node Memory Pressure

Alert: NodeMemoryPressure (Warning)

Symptoms:
- Alert fires when node memory > 85% utilization
- Pods may be evicted if pressure continues
- Node status may show MemoryPressure

Investigation:
  kubectl top node <node-name>
  kubectl top pods -A --sort-by=memory | head -20
  
  # Check which namespace/pod using most memory
  kubectl top pods -n <namespace> --sort-by=memory

Root Causes:
- Application memory leak
- Too many pods on single node
- Pod memory limits too high

Resolution:

If specific pod using too much:
  # Kill and restart pod
  kubectl delete pod <pod-name> -n <namespace>
  
  # Or reduce memory limit
  kubectl set resources pod <pod-name> -n <namespace> \
    -c <container> --limits=memory=512Mi

If too many pods:
  # Cordon node to stop new pod scheduling
  kubectl cordon <node-name>
  
  # Drain some pods to other nodes
  kubectl delete pod <pod-name> -n <namespace>
  
  # Or reduce replica count
  kubectl scale deployment <name> --replicas=2 -n <namespace>

Monitor:
  watch kubectl top node <node-name>
  watch kubectl top pods -A

---

## Storage Issues

### PVC Capacity Low

Alert: PersistentVolumeClaimCapacityLow (Warning) / Critical (< 5%)

Symptoms:
- PVC usage above 90% or 95%
- Alert fires from kubelet volume stats
- Application may fail due to full storage

Investigation:
  kubectl get pvc -n <namespace>
  kubectl get pvc <pvc-name> -n <namespace> -o yaml
  
  # Check actual usage
  kubectl exec -it <pod-using-pvc> -n <namespace> -- \
    df -h /path/to/mount

Root Causes:
- Application writing logs/data faster than expected
- No log rotation configured
- Data not being cleaned up

Resolution:

For data directories:
  # Check what's taking space
  kubectl exec -it <pod> -n <namespace> -- \
    du -sh /path/to/mount/*
  
  # Clean old data if safe
  kubectl exec -it <pod> -n <namespace> -- \
    rm -rf /path/to/mount/old-data/
  
  # Or expand PVC
  kubectl patch pvc <pvc-name> -n <namespace> -p \
    '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'

For logs:
  # Enable log rotation if not configured
  # Or delete old logs
  kubectl exec -it <pod> -n <namespace> -- \
    rm /var/log/app.log.*

For databases:
  # Connect to database and clean old data
  # e.g., delete old records, vacuum database

Monitor:
  watch kubectl get pvc -n <namespace>
  
  # Setup alerts to prevent reaching critical
  # See manifests/monitoring/prometheus-rules.yaml

---

## Observability Issues

### Grafana Down

Alert: GrafanaDown (Critical)

Symptoms:
- Cannot access Grafana UI
- Port-forward fails: connection refused
- Grafana pod is not running

Investigation:
  kubectl get pods -n monitoring | grep grafana
  kubectl describe pod <grafana-pod> -n monitoring
  kubectl logs <grafana-pod> -n monitoring

Root Causes:
- Pod crash
- Storage volume issue
- Configuration error
- Resource limits exceeded

Resolution:

Check pod status:
  kubectl get pod <grafana-pod> -n monitoring
  
If Pending:
  kubectl describe pod <grafana-pod> -n monitoring
  # Check for resource/scheduling issues
  # See "Pod Not Healthy" runbook

If CrashLoopBackOff:
  kubectl logs <grafana-pod> -n monitoring
  kubectl describe pod <grafana-pod> -n monitoring
  
  # Check storage
  kubectl get pvc -n monitoring | grep grafana
  
  # Restart
  kubectl delete pod <grafana-pod> -n monitoring

Access Grafana:
  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
  # Visit http://localhost:3000

If still down:
  # Rollout restart
  kubectl rollout restart deployment kube-prometheus-stack-grafana -n monitoring
  
  # Monitor
  watch kubectl get pods -n monitoring | grep grafana

---

### Prometheus Config Reload Failed

Alert: PrometheusConfigReloadFailed (Warning)

Symptoms:
- Prometheus alert fires
- New alert rules not being evaluated
- Configuration change not taking effect

Investigation:
  kubectl logs -n monitoring deployment/prometheus-operator
  kubectl logs -n monitoring prometheus-kube-prometheus-prometheus-0
  
  # Check Prometheus UI
  kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
  # Visit http://localhost:9090/config
  
  # Check status
  kubectl get prometheus -n monitoring

Root Causes:
- Invalid YAML in PrometheusRule
- PrometheusRule YAML syntax error
- Secret/ConfigMap reference not found

Resolution:

Validate new configuration:
  # Lint YAML files
  yamllint manifests/monitoring/prometheus-rules.yaml
  
  # Check Prometheus operator logs for specific error
  kubectl logs -n monitoring deployment/prometheus-operator --tail=50 | grep -i error

Fix YAML:
  # Edit file
  vim manifests/monitoring/prometheus-rules.yaml
  
  # Validate
  kubectl apply -f manifests/monitoring/prometheus-rules.yaml --dry-run=client
  
  # Apply
  kubectl apply -f manifests/monitoring/prometheus-rules.yaml

Restart Prometheus:
  # Delete statefulset pod (will be recreated)
  kubectl delete pod prometheus-kube-prometheus-prometheus-0 -n monitoring
  
  # Monitor restart
  kubectl logs -f prometheus-kube-prometheus-prometheus-0 -n monitoring -n kube-system

Verify:
  # Check Prometheus targets loaded
  curl http://localhost:9090/api/v1/targets
  
  # Check alert rules loaded
  curl http://localhost:9090/api/v1/rules

---

## GitOps Issues

### ArgoCD App Sync Failure

Alert: ArgoCDAppSyncFailure (Warning)

Symptoms:
- ArgoCD UI shows "OutOfSync" or "Failed"
- `kubectl get applications -n argocd` shows SyncStatus: Failed
- Application resources not updating

Investigation:
  argocd app get <app-name>
  kubectl describe application <app-name> -n argocd
  kubectl logs -n argocd deployment/argocd-application-controller

Root Causes:
- Git repository not accessible
- Helm chart syntax error
- Kustomize build failure
- Resource conflicts
- RBAC permissions issue

Resolution:

Check Git access:
  # Verify SSH key in ArgoCD
  argocd repo list
  argocd repo get https://github.com/vietcgi/kind-gitops-platform
  
  # If SSH key invalid, update:
  argocd repo add <repo-url> --ssh-key-path ~/.ssh/id_rsa

Check Helm values:
  # Manually test Helm template
  helm template <app> helm/<chart> -f values.yaml --validate
  
  # Look for YAML syntax errors
  yamllint helm/<chart>/values.yaml

Check git branch:
  # Verify correct branch is set
  kubectl get application <app-name> -n argocd -o yaml | grep targetRevision
  
  # If using wrong branch
  kubectl patch application <app-name> -n argocd -p \
    '{"spec":{"source":{"targetRevision":"main"}}}'

Manual sync:
  argocd app sync <app-name>
  argocd app sync <app-name> --prune --force
  
  # Monitor sync
  watch argocd app get <app-name>

Check recent commits:
  # Ensure recent commit doesn't have breaking changes
  git log --oneline -5

---

### ArgoCD Health Degraded

Alert: ArgoCDAppHealthDegraded (Warning)

Symptoms:
- ArgoCD shows Health: Degraded
- Some resources not healthy
- Pods not ready, services unavailable

Investigation:
  argocd app get <app-name>
  kubectl get application <app-name> -n argocd -o yaml
  
  # Check resource health
  argocd app resources <app-name>
  
  # Detailed resource status
  kubectl get all -n <app-namespace>

Root Causes:
- Pod not ready
- Service endpoint not available
- Resource stuck in failed state
- Image pull failure

Resolution:

Check pod health:
  kubectl get pods -n <app-namespace>
  kubectl describe pod <unhealthy-pod> -n <app-namespace>
  
  # See "Pod Not Healthy" runbook for resolution

Check service:
  kubectl get svc -n <app-namespace>
  kubectl get endpoints <service> -n <app-namespace>
  
  # If no endpoints, pods not ready

Check resource status:
  kubectl get deployment <name> -n <app-namespace>
  kubectl get statefulset <name> -n <app-namespace>
  
  # Review events
  kubectl get events -n <app-namespace> --sort-by='.lastTimestamp'

Recovery:
  # If resources stuck, manually delete and resync
  kubectl delete pod <pod-name> -n <app-namespace>
  
  # Or force ArgoCD resync
  argocd app sync <app-name> --force

Monitor:
  watch argocd app get <app-name>
  watch kubectl get pods -n <app-namespace>

---

## Certificate Issues

### Certificate Expiring Soon

Alert: CertificateExpiringSoon (Warning - 90 days) / Critical (7 days)

Symptoms:
- Alert fires when certificate expires in < 90 days (warning) or < 7 days (critical)
- `kubectl get certificate -A` shows certificate near expiration

Investigation:
  kubectl get certificate -n <namespace>
  kubectl describe certificate <cert-name> -n <namespace>
  
  # Check expiration date
  kubectl get certificate <cert-name> -n <namespace> -o jsonpath='{.status.renewalTime}'
  
  # Check issued secret
  kubectl get secret <secret-name> -n <namespace> -o yaml

Root Causes:
- Certificate renewal not configured
- Cert-Manager not running
- Cluster issuer not configured
- Automatic renewal disabled

Resolution:

Verify Cert-Manager:
  kubectl get pods -n cert-manager
  kubectl logs -n cert-manager deployment/cert-manager
  
  # Should show: "Syncing certificate" messages

Check Certificate CRD:
  kubectl get certificate <cert-name> -n <namespace> -o yaml
  
  # Verify:
  # - issuerRef: pointing to valid issuer
  # - renewBefore: set to trigger renewal early
  # - dnsNames: correct domain names

If renewal not working:
  # Force renewal by triggering secret rotation
  kubectl delete secret <secret-name> -n <namespace>
  
  # Cert-Manager will recreate it
  kubectl get secret <secret-name> -n <namespace> --watch
  
  # Monitor Cert-Manager logs
  kubectl logs -f -n cert-manager deployment/cert-manager

If issuer issue:
  kubectl describe issuer <issuer-name> -n <namespace>
  kubectl describe clusterissuer <issuer-name>
  
  # Check issuer status and conditions
  # Look for errors in "Status" section

Manual renewal option:
  # Create new certificate object
  kubectl patch certificate <cert-name> -n <namespace> \
    -p '{"spec":{"renewBefore":"2160h"}}'  # 90 days

Monitor:
  watch kubectl get certificate <cert-name> -n <namespace>
  kubectl logs -f -n cert-manager deployment/cert-manager

---

## Vault Issues

### Vault Sealed

Alert: VaultSealed (Critical)

Symptoms:
- Vault pod running but sealed
- Vault API returns HTTP 503
- Cannot read/write secrets

Investigation:
  kubectl get pods -n vault
  kubectl logs <vault-pod> -n vault
  
  # Check Vault status
  kubectl port-forward -n vault svc/vault 8200:8200
  curl http://localhost:8200/v1/sys/health

Root Causes:
- Vault crashed and restarted (automatic seal)
- Seal key lost/corrupted
- Storage backend issue

Resolution:

If Vault not running:
  kubectl get pod <vault-pod> -n vault
  kubectl describe pod <vault-pod> -n vault
  
  # Check logs
  kubectl logs <vault-pod> -n vault
  
  # Restart if needed
  kubectl delete pod <vault-pod> -n vault

Unseal Vault:
  # Vault automatically unseals if using cloud KMS
  # For development, uses integrated storage
  
  # Check unsealed status
  kubectl port-forward -n vault svc/vault 8200:8200
  curl http://localhost:8200/v1/sys/health | jq .sealed
  
  # If still sealed after pod restart, may need manual unseal
  # This requires unseal keys (keep in safe location)

Prevent future sealing:
  # Ensure storage backend is healthy
  kubectl get pvc -n vault
  kubectl describe pvc <vault-pvc> -n vault
  
  # Monitor storage capacity
  # See "PVC Capacity Low" runbook if needed

Recovery:
  # After fixing issue, force Vault restart
  kubectl rollout restart statefulset/vault -n vault
  
  # Monitor
  kubectl logs -f <vault-pod> -n vault

---

## Emergency Procedures

### Cluster Recovery from Backups

If cluster is severely damaged:

1. Backup current state (if possible):
     velero backup create emergency-backup

2. Restore from latest good backup:
     velero restore create --from-backup <backup-name>

3. Monitor restoration:
     velero restore get
     watch kubectl get pods -A

4. Verify critical services:
     kubectl get applications -n argocd
     kubectl get svc -A

5. Restore ArgoCD state:
     argocd app sync --all --force

See "Disaster Recovery" section in OPERATIONS.md for detailed backup/restore procedures.

---

## Key Exit Codes

Container exit codes:
- 1: General error
- 2: Misuse of shell command
- 125: Run error (Docker/container runtime)
- 126: Command invoked cannot execute
- 127: Command not found
- 128+N: Fatal signal N (128+9=137 for SIGKILL/OOMKilled)
- 137: OOMKilled (exit code 128+9)
- 139: SIGSEGV (segmentation fault)
- 143: SIGTERM (graceful shutdown)

---

## Contacting Support

For issues not covered in this runbook:

1. Check pod logs
2. Review Prometheus/Grafana dashboards
3. Consult ARCHITECTURE.md and CONFIGURATION.md
4. Check recent git commits for breaking changes
5. Open GitHub issue if needed

