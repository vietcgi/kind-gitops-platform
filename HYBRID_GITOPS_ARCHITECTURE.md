# Hybrid GitOps Bootstrap Architecture (v2)

## Overview

This document describes the **hybrid GitOps architecture** that combines intelligent imperative bootstrap with declarative GitOps management. The system ensures a healthy, self-healing cluster where ArgoCD manages everything, including itself.

### Key Principles

1. **Smart Bootstrap**: deploy.sh orchestrates the initial cluster setup intelligently
2. **Complete GitOps**: ArgoCD manages CoreDNS, Cilium, ArgoCD itself, and all applications
3. **Active Monitoring**: 20-minute health monitoring ensures successful bootstrap
4. **Self-Healing**: ArgoCD's automated sync keeps the cluster in desired state
5. **Single Source of Truth**: Git repository is the canonical state for all configurations

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         deploy.sh (Smart Orchestrator)              │
└─────────────────────────────────────────────────────────────────────┘
         │
         ├─── PHASE 1: Network Prerequisites (Blocking)
         │    ├─ Create KIND cluster
         │    ├─ Wait for API server
         │    ├─ Patch CoreDNS with resource limits
         │    └─ Wait for CoreDNS ready
         │
         ├─── PHASE 2: Install ArgoCD (Blocking)
         │    ├─ Create argocd namespace
         │    ├─ Apply official ArgoCD manifests
         │    ├─ Wait for ArgoCD server ready
         │    ├─ Wait for application controller ready
         │    └─ Wait for repo server ready
         │
         ├─── PHASE 3: Bootstrap GitOps (Minimal Wait)
         │    └─ Apply root-app.yaml (single entry point)
         │
         └─── PHASE 4: Active Health Monitoring (20 minutes)
              ├─ Monitor cluster node health
              ├─ Track critical app sync status (root-app, coredns-config, cilium)
              ├─ Verify pod readiness (CoreDNS, Cilium, ArgoCD)
              ├─ Accumulate health statistics
              └─ Generate final health report

                    ↓ (After PHASE 4)

         ┌──────────────────────────────────────────────────────┐
         │  Healthy Cluster Ready for Production Use            │
         │  All further management via ArgoCD Self-Healing Loop │
         └──────────────────────────────────────────────────────┘
```

---

## Detailed Phases

### Phase 1: Network Prerequisites

**Purpose**: Establish the cluster with essential networking components

**Actions**:
```bash
1. Create KIND cluster with kind-config.yaml
2. Wait for API server availability (300s timeout)
3. Patch CoreDNS with production resource limits:
   - Limits: CPU 100m, Memory 64Mi
   - Requests: CPU 50m, Memory 32Mi
4. Wait for CoreDNS pods to be ready (300s timeout)
```

**Exit Criteria**:
- CoreDNS pods are running and ready
- All nodes are Ready
- API server is responsive

**Why This Phase?**
- CoreDNS must be ready BEFORE ArgoCD can resolve DNS during sync
- Resource limits prevent CoreDNS from consuming excessive cluster resources
- Acts as a sanity check that basic cluster networking works

---

### Phase 2: Install ArgoCD

**Purpose**: Deploy ArgoCD as the GitOps orchestrator

**Actions**:
```bash
1. Create argocd namespace
2. Apply official ArgoCD manifests from upstream (stable)
3. Wait for argocd-server deployment ready (300s timeout)
4. Wait for argocd-application-controller deployment ready (300s timeout)
5. Wait for argocd-repo-server deployment ready (300s timeout)
```

**Exit Criteria**:
- All ArgoCD deployments are running and ready
- ArgoCD API is accessible
- Application controller can reconcile applications

**Why This Phase?**
- ArgoCD requires its three main components to be operational
- Ensures ArgoCD is ready to process the GitOps bootstrap
- Validates that cluster has sufficient resources for ArgoCD

---

### Phase 3: Bootstrap GitOps

**Purpose**: Trigger the declarative GitOps management cascade

**Actions**:
```bash
1. Apply argocd/bootstrap/root-app.yaml
   - This is the SINGLE entry point for all GitOps configuration
   - Syncs from: argocd/config/ in Git repository
   - Enables automated sync with self-healing
   - Includes retry logic (5 attempts, exponential backoff)

2. Wait 5 seconds for root-app to be created in API server
```

**Root App Manifest**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/vietcgi/kubernetes-platform-stack
    targetRevision: main
    path: argocd/config

  syncPolicy:
    automated:
      prune: true      # Remove resources not in Git
      selfHeal: true   # Re-sync if cluster drifts
    retry:
      limit: 5
      backoff: exponential
```

**GitOps Cascade** (triggered by root-app):
```
root-app (argocd/config)
├── _namespace.yaml
│   └── Syncs from: argocd/applications/namespaces
│       └── Creates 12+ custom namespaces
│
├── _coredns.yaml
│   └── Cilium Application
│       └── Syncs from: https://helm.cilium.io (Helm chart)
│       └── Enables: eBPF, Hubble, network policies
│
├── _cilium.yaml
│   └── CoreDNS Configuration Application
│       └── Syncs from: argocd/applications/coredns
│       └── Applies resource limits and patches
│
├── _argocd-config.yaml
│   └── ArgoCD Self-Management Application
│       └── Syncs from: argocd/applications/argocd-app
│       └── Allows ArgoCD to manage itself
│
├── _infra-apps.yaml
│   └── Infrastructure Applications Aggregator
│       └── Syncs from: argocd/applications/
│       └── Manages: Kong, sealed-secrets, cert-manager, etc.
│
└── _platform-apps.yaml
    └── Platform ApplicationSet Generator
        └── Syncs from: argocd/applicationsets/
        └── Generates 14+ business applications dynamically
```

**Exit Criteria**:
- root-app is created in ArgoCD
- Initial sync attempt starts
- Proceed immediately to Phase 4 (don't wait for sync completion)

---

### Phase 4: Active Health Monitoring (20 Minutes)

**Purpose**: Ensure successful bootstrap and cluster stability

**Duration**: 1200 seconds (20 minutes)

**Monitoring Parameters**:
- Check interval: 10 seconds
- Monitoring loop: 120 checks over 20 minutes

**What Gets Monitored**:

#### 1. Cluster Node Health
```bash
Checks: All nodes are Ready
Returns: 0 (healthy) if all nodes Ready, 1 (unhealthy) otherwise
```

#### 2. Critical Application Sync Status
```bash
Monitors:
- root-app (main orchestrator)
- coredns-config (DNS configuration)
- cilium (network plugin)

Status Check: ApplicationStatus.sync.status == "Synced"
Healthy Count: Tracked per app
Success Threshold: App considered healthy once synced
```

#### 3. Critical Application Health Status
```bash
Monitors:
- root-app (main orchestrator)

Health Check: ApplicationHealth.status == "Healthy"
Considerations: Healthy = all resources operational
```

#### 4. Pod Readiness
```bash
Monitors:
- CoreDNS pods (label: k8s-app=kube-dns)
- Cilium pods (label: k8s-app=cilium)
- ArgoCD pods (namespace: argocd)

Readiness Check: Pod.status.phase == "Running" AND all containers ready
Pod Count Report: X/Y pods running in namespace
```

**Health Check Output** (real-time):
```
[0m] Monitoring in progress... 20m 0s remaining
[1m] Monitoring in progress... 19m 0s remaining
...
[19m] Monitoring in progress... 1m 0s remaining
[20m] Monitoring completed!
```

**Final Health Report**:
```
root-app             Sync: Synced      [✓] Health: Healthy     [✓] Rev: abc1234
coredns-config       Sync: Synced      [✓] Health: Healthy     [✓] Rev: def5678
cilium               Sync: Synced      [✓] Health: Healthy     [✓] Rev: ghi9012

argocd               Pods: 6/6  [✓]
kube-system          Pods: 8/8  [✓]

Nodes ready: 1/1
```

**Monitoring Algorithm**:

```bash
FOR each 10-second interval DURING 20 minutes:

  1. Check node health
  2. Check root-app sync status
  3. Check coredns-config sync status
  4. Check cilium sync status
  5. Check root-app health status
  6. Check CoreDNS pod readiness
  7. Check Cilium pod readiness

  8. If check passed:
     - Increment counter for that app/component

  9. Display progress bar with elapsed/remaining time

  10. Sleep 10 seconds before next check

AFTER 20 minutes:

  1. Display final status of all apps
  2. Display pod count in critical namespaces
  3. Display cluster node status
  4. Show next steps for user
```

**Health Determination**:

An app/component is considered healthy when:
- **Synced**: `ApplicationStatus.sync.status == "Synced"`
- **Healthy**: `ApplicationHealth.status == "Healthy"`
- **Pods Ready**: All pods with selector are Running and Ready

---

## File Structure

```
kubernetes-platform-stack/
├── deploy.sh                              # Main orchestrator (enhanced with monitoring)
├── HYBRID_GITOPS_ARCHITECTURE.md         # This file
├── kind-config.yaml                      # KIND cluster configuration
├── scripts/
│   └── health-check.sh                   # Health monitoring utilities (sourced by deploy.sh)
├── argocd/
│   ├── bootstrap/
│   │   └── root-app.yaml                 # Single GitOps entry point
│   ├── config/
│   │   ├── kustomization.yaml            # Main umbrella (includes CoreDNS + Cilium NOW)
│   │   ├── _namespace.yaml               # Namespace application
│   │   ├── _coredns.yaml                 # CoreDNS configuration (NOW ENABLED)
│   │   ├── _cilium.yaml                  # Cilium CNI (NOW ENABLED)
│   │   ├── _argocd-config.yaml           # ArgoCD self-management
│   │   ├── _infra-apps.yaml              # Infrastructure apps aggregator
│   │   └── _platform-apps.yaml           # Platform apps generator
│   └── applications/
│       ├── namespaces/                   # Namespace definitions
│       ├── argocd-app/                   # ArgoCD RBAC and self-config
│       ├── coredns/                      # CoreDNS patches
│       └── [other apps]/
└── argocd/
    └── applicationsets/
        └── platform-apps.yaml            # Platform ApplicationSet generator
```

---

## What Changed from Previous Version

### Before (100% GitOps - Broke)
- Tried to manage CoreDNS and Cilium via ArgoCD immediately
- Circular dependency: ArgoCD needed to sync network configs, but networking needed to work for sync
- CoreDNS couldn't be patched before cluster became available
- Result: Bootstrap failures and cluster instability

### Now (Smart Hybrid Approach - Works)

#### deploy.sh Responsibilities (Imperative - Blocking)
1. ✅ Create KIND cluster
2. ✅ Patch CoreDNS with resource limits (before ArgoCD takes over)
3. ✅ Install ArgoCD components
4. ✅ Apply root-app to trigger GitOps cascade
5. ✅ **Monitor health for 20 minutes to ensure stability**

#### ArgoCD Responsibilities (Declarative - Ongoing)
1. ✅ Manage CoreDNS configuration (via coredns-config application)
2. ✅ Manage Cilium installation (via cilium application)
3. ✅ Manage itself (via argocd-config application)
4. ✅ Manage all infrastructure apps (Kong, sealed-secrets, etc.)
5. ✅ Manage all platform applications (generated via ApplicationSet)
6. ✅ **Self-heal all resources if they drift from Git**

#### Key Improvement: Monitoring
- **Before**: deploy.sh just applied root-app and exited
- **Now**: deploy.sh actively monitors for 20 minutes to ensure:
  - ✅ All critical apps sync successfully
  - ✅ Pods are healthy and running
  - ✅ Cluster nodes are ready
  - ✅ Provides detailed health report at end

---

## Flow Diagram: What Happens When deploy.sh Runs

```
┌─────────────────────────────────────────────────┐
│ 1. User runs: bash deploy.sh                    │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ 2. Create KIND cluster                          │
│    (kind create cluster --config kind-config)   │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ 3. PHASE 1: CoreDNS Ready                       │
│    - Patch resource limits                      │
│    - Wait for DNS pods                          │
│    - Verify cluster networking                  │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ 4. PHASE 2: Install ArgoCD                      │
│    - Create namespace                           │
│    - Apply manifests                            │
│    - Wait for all components ready              │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ 5. PHASE 3: Apply root-app.yaml                 │
│    - Single GitOps entry point                  │
│    - Triggers cascade of applications           │
│    - Don't wait for completion                  │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ 6. PHASE 4: Monitor for 20 minutes              │
│    - Check app sync status                      │
│    - Check pod health                           │
│    - Check node readiness                       │
│    - Generate health report                     │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ 7. Bootstrap Complete!                          │
│    - Cluster is healthy and ready               │
│    - ArgoCD manages everything                  │
│    - Self-healing loop active                   │
│    - Users can proceed to next steps            │
└─────────────────────────────────────────────────┘
```

---

## Using the Health Check Utilities

The `scripts/health-check.sh` provides reusable functions:

### Available Functions

```bash
# Check if nodes are ready
check_node_health
# Returns: 0 (healthy), 1 (unhealthy)

# Check if app is synced
check_argocd_app_sync "app-name"
# Returns: 0 (synced), 1 (not synced)

# Check if app is healthy
check_argocd_app_health "app-name"
# Returns: 0 (healthy), 1 (unhealthy)

# Check pod readiness by label
check_pod_health "namespace" "label=selector"
# Returns: 0 (all ready), 1 (some not ready)

# Display app status
get_app_status "app-name"
# Output: formatted status line

# Display pod count
get_pod_count "namespace"
# Output: formatted pod count

# Monitor app until synced (with timeout)
monitor_app_sync "app-name" "timeout-seconds"
# Waits for app to sync or timeout

# Get detailed app status
get_detailed_app_status "app-name"
# Output: full YAML status

# Monitor all apps in namespace
monitor_all_apps "namespace" "interval"
# Continuous monitoring loop

# Check overall cluster stability
check_cluster_stability
# Returns: 0 (stable), 1 (unstable)

# Get complete cluster status report
get_cluster_status
# Output: formatted report
```

### Example Usage After Bootstrap

```bash
# Manually check health after deploy.sh completes
source scripts/health-check.sh

# Check if everything is healthy
get_cluster_status

# Monitor apps until they're all synced
monitor_all_apps argocd 5

# Check a specific app
get_app_status root-app
check_argocd_app_health root-app
```

---

## Key Configuration Details

### Root Application (_bootstrap/root-app.yaml)

```yaml
syncPolicy:
  automated:
    prune: true      # Remove resources not in Git (cleanup)
    selfHeal: true   # Auto-resync if cluster drifts
  syncOptions:
    - CreateNamespace=true  # Create destinations if needed
    - PruneLast=true        # Prune after all resources applied
  retry:
    limit: 5                    # Retry 5 times on failure
    backoff:
      factor: 2                 # Exponential: 5s, 10s, 20s, 40s, 80s
      maxDuration: 3m           # Max wait between retries
```

### Cilium Application (_config/_cilium.yaml)

```yaml
Helm Chart: cilium/cilium:1.18.3
Values:
  kubeProxyReplacement: strict    # Replace kube-proxy entirely
  ebpf:
    enabled: true                 # Use eBPF dataplane
  networkPolicy:
    enabled: true                 # Enforce network policies
  hubble:
    enabled: true                 # Network observability
  Resource Limits (for KIND):
    limits: 500m CPU / 512Mi RAM
    requests: 100m CPU / 128Mi RAM
```

### CoreDNS Application (_config/_coredns.yaml)

```yaml
Source: argocd/applications/coredns/ (Git repository)
Syncs: Patches and configuration to kube-system namespace
Manages: CoreDNS deployment, resource limits, custom configs
Resource Limits (patched in PHASE 1):
  limits: 100m CPU / 64Mi RAM
  requests: 50m CPU / 32Mi RAM
```

### ArgoCD Self-Config (_config/_argocd-config.yaml)

```yaml
Source: argocd/applications/argocd-app/ (Git repository)
Special: Uses RespectIgnoreDifferences=true
Allows: ArgoCD application controller to modify itself
Manages: RBAC, app controller permissions, config
Result: ArgoCD updates itself without manual intervention
```

---

## Troubleshooting

### Problem: deploy.sh hangs in Phase 2

**Symptom**: Script appears stuck waiting for ArgoCD

**Solutions**:
```bash
# Check if ArgoCD pods are running
kubectl get pods -n argocd

# Check pod logs for errors
kubectl logs -n argocd deployment/argocd-server
kubectl logs -n argocd deployment/argocd-application-controller

# If stuck > 10 minutes, increase timeout
STARTUP_TIMEOUT=900 bash deploy.sh
```

### Problem: Phase 4 monitoring shows unhealthy apps

**Symptom**: Health report shows "OutOfSync" or "Unhealthy"

**Solutions**:
```bash
# Check app sync status
kubectl get application root-app -n argocd -o yaml | grep -A 20 status:

# Check ArgoCD application controller logs
kubectl logs -n argocd deployment/argocd-application-controller | tail -50

# Manually trigger resync
kubectl patch application root-app -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Wait for next monitoring cycle or manually run health checks
source scripts/health-check.sh
get_cluster_status
```

### Problem: CoreDNS or Cilium not becoming healthy

**Symptom**: Pods not ready, network not working

**Solutions**:
```bash
# Check CoreDNS pod status
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns

# Check Cilium pod status
kubectl get pods -n kube-system -l k8s-app=cilium -o wide

# Check Cilium logs
kubectl logs -n kube-system -l k8s-app=cilium | head -100

# Verify KIND cluster has sufficient resources
docker ps | grep kind
docker stats  # Check memory/CPU usage
```

### Problem: Want to skip monitoring phase

**Solution**:
```bash
# Set monitoring duration to 0
MONITORING_DURATION=0 bash deploy.sh
```

---

## Production Considerations

### What This Architecture Provides

✅ **Reliable Bootstrap**
- Multi-phase approach ensures dependencies satisfied
- CoreDNS ready before ArgoCD syncs
- ArgoCD ready before GitOps cascade

✅ **Visibility**
- 20-minute active monitoring ensures success
- Health report shows cluster readiness
- Real-time progress feedback

✅ **Maintainability**
- Single source of truth in Git
- ArgoCD manages all updates
- Drift detection and self-healing

✅ **Scalability**
- Add new apps via Git push
- ApplicationSet generates apps dynamically
- Consistent deployment across environments

### What to Customize

For production environments, consider:

1. **Monitoring Duration** (currently 20 min)
   - Adjust based on cluster size: `MONITORING_DURATION=1800 bash deploy.sh`

2. **Resource Limits** (currently set for KIND)
   - Update in `_cilium.yaml` and `_coredns.yaml` for production specs

3. **Helm Chart Versions**
   - Pin specific Cilium versions in `_cilium.yaml`
   - Update quarterly for security patches

4. **Retry Strategy**
   - Increase retry limits for flaky environments
   - Adjust backoff duration for slow deployments

5. **Network Configuration**
   - Update k8sServiceHost/Port for non-local clusters
   - Adjust Cilium network policies for your topology

---

## Related Documentation

- `GITOPS_BOOTSTRAP.md` - Original GitOps bootstrap architecture
- `argocd/bootstrap/root-app.yaml` - Root application definition
- `argocd/config/` - ArgoCD configuration manifests
- `scripts/health-check.sh` - Health check utility functions

---

## Summary

This hybrid architecture delivers:

| Aspect | Previous (Broken) | Now (Hybrid) |
|--------|-------------------|-------------|
| **CoreDNS** | Managed by ArgoCD from start (failed) | Pre-patched by deploy.sh, managed by ArgoCD after |
| **Cilium** | Managed by ArgoCD from start (failed) | Pre-installed by deploy.sh, managed by ArgoCD after |
| **ArgoCD** | Self-managing from bootstrap | Installed imperatively, then self-manages |
| **Monitoring** | Manual (watch kubectl) | Automatic (20 min active monitoring) |
| **Reliability** | Bootstrap often failed | Bootstrap succeeds, cluster verified healthy |
| **Future Updates** | All via Git/ArgoCD | All via Git/ArgoCD |

**Result**: A robust, observable, GitOps-driven Kubernetes platform that starts reliably and maintains itself.
