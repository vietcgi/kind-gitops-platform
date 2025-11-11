# Bootstrap Quick Start Guide

## What Changed

✅ **ArgoCD now manages CoreDNS, Cilium, and itself**
- Previously: CoreDNS/Cilium were only in deploy.sh
- Now: Both managed by ArgoCD after initial setup

✅ **deploy.sh now monitors cluster health for 20 minutes**
- Ensures bootstrap succeeds
- Provides health report
- Validates critical apps and pods are ready

✅ **Hybrid approach**: Best of both worlds
- Reliable imperative bootstrap (deploy.sh)
- Declarative GitOps management (ArgoCD)
- 20 minute health verification

---

## Quick Start

### 1. Run Deploy (One Command)

```bash
bash deploy.sh
```

**What happens**:
- Phase 1 (2-3 min): Create KIND cluster, setup CoreDNS
- Phase 2 (1-2 min): Install ArgoCD
- Phase 3 (10s): Trigger GitOps cascade via root-app
- Phase 4 (20 min): Active health monitoring
- **Total time**: ~25 minutes

### 2. Wait for Health Report

The script displays:
```
═══════════════════════════════════════════════════════════════════
root-app             Sync: Synced      [✓] Health: Healthy     [✓]
coredns-config       Sync: Synced      [✓] Health: Healthy     [✓]
cilium               Sync: Synced      [✓] Health: Healthy     [✓]

argocd               Pods: 6/6  [✓]
kube-system          Pods: 8/8  [✓]

Nodes ready: 1/1
✓ Cluster bootstrap complete!
═══════════════════════════════════════════════════════════════════
```

### 3. You're Done! 🎉

Your cluster is:
- ✅ Bootstrapped and healthy
- ✅ All critical components synced and ready
- ✅ Running ArgoCD for self-management
- ✅ Ready for production use

---

## After Bootstrap

### Monitor Applications in Real-Time

```bash
# Watch all ArgoCD applications
kubectl get applications -n argocd -w

# Watch all resources syncing
kubectl get all -A -w
```

### Access ArgoCD UI

```bash
# Port forward to ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Open browser: https://localhost:8080
# Default credentials: admin / (run command below for password)
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```

### Check Cluster Health Manually

```bash
# Source health check functions
source scripts/health-check.sh

# Get full cluster status
get_cluster_status

# Check specific app
get_app_status cilium
get_app_status coredns-config
get_app_status root-app

# Monitor all apps (continuous)
monitor_all_apps argocd 5  # Update every 5 seconds
```

### Add New Applications

New apps are deployed via Git:

1. Create app manifests in `argocd/applications/` or use ApplicationSet in `argocd/applicationsets/`
2. Push to main branch
3. ArgoCD auto-syncs (usually within 3 minutes)

Example ApplicationSet is already in `argocd/applicationsets/platform-apps.yaml`

---

## Customization

### Increase Monitoring Duration

```bash
# Monitor for 30 minutes instead of 20
MONITORING_DURATION=1800 bash deploy.sh
```

### Skip Monitoring Phase

```bash
# Bootstrap only, no monitoring
MONITORING_DURATION=0 bash deploy.sh
```

### Adjust Resource Limits for Different Cluster Size

For **production clusters**, update `argocd/config/_cilium.yaml`:

```yaml
resources:
  limits:
    cpu: 2000m      # Increase from 500m
    memory: 2Gi     # Increase from 512Mi
  requests:
    cpu: 500m       # Increase from 100m
    memory: 512Mi   # Increase from 128Mi
```

Then push to Git - ArgoCD will automatically update Cilium.

### Change Cilium Version

In `argocd/config/_cilium.yaml`:

```yaml
source:
  targetRevision: 1.19.0  # Update from 1.18.3
  chart: cilium
```

Push to Git - ArgoCD will upgrade.

---

## Architecture Overview

```
┌──────────────────────┐
│    deploy.sh         │  (Smart Orchestrator)
└──────────────────────┘
         │
    ┌────┴────┬────────┬────────┐
    │          │        │        │
    v          v        v        v
┌─────┐  ┌─────────┐ ┌──────┐ ┌──────────────┐
│ KIND│  │ ArgoCD  │ │ Root │ │ 20min Health │
│ Clus│  │Install  │ │ App  │ │ Monitor      │
└─────┘  └─────────┘ └──────┘ └──────────────┘
         │
    ┌────┴────────────────────────────────────┐
    │  ArgoCD Self-Healing Loop (Forever)     │
    └────────────────────────────────────────┘
         │
    ┌────┴─────┬──────────┬──────────┐
    │           │          │          │
    v           v          v          v
┌─────────┐ ┌────────┐ ┌──────────┐ ┌───────────┐
│CoreDNS  │ │Cilium  │ │ ArgoCD   │ │ Platform  │
│(ArgoCD) │ │(ArgoCD)│ │(ArgoCD)  │ │ Apps(GitOps)
└─────────┘ └────────┘ └──────────┘ └───────────┘
```

---

## Troubleshooting

### Problem: Deploy script hangs

**Check if it's really hung**:
```bash
# In another terminal, monitor progress
kubectl get applications -n argocd -w
kubectl get pods -n argocd -w
```

**If actually stuck > 10 minutes**:
```bash
# Increase timeout and restart
STARTUP_TIMEOUT=1200 bash deploy.sh
```

### Problem: Health monitor shows "OutOfSync"

This is **normal during bootstrap** - sync happens gradually:
1. First: Namespaces created
2. Then: CoreDNS and Cilium resources
3. Finally: All apps

Watch it sync:
```bash
kubectl get applications -n argocd -w
```

### Problem: Pods not becoming ready

```bash
# Check pod status
kubectl get pods -n kube-system -o wide

# Check pod logs
kubectl logs -n kube-system -l k8s-app=coredns
kubectl logs -n kube-system -l k8s-app=cilium

# Check cluster resources
docker stats  # If using Docker Desktop
```

### Problem: Want to restart bootstrap

```bash
# Delete the KIND cluster
kind delete cluster --name platform

# Re-run deploy
bash deploy.sh
```

---

## Files Modified/Created

| File | What Changed |
|------|--------------|
| `deploy.sh` | **Completely rewritten** - Added 4 phases, monitoring loop, health checks |
| `scripts/health-check.sh` | **NEW** - Health check utility functions |
| `argocd/config/_cilium.yaml` | Updated - Now includes eBPF, network policies, resource limits |
| `argocd/config/_coredns.yaml` | Updated - Better config, retry logic, sync options |
| `argocd/config/kustomization.yaml` | Updated - Added `_cilium.yaml` and `_coredns.yaml` resources |
| `HYBRID_GITOPS_ARCHITECTURE.md` | **NEW** - Complete architecture documentation |
| `BOOTSTRAP_QUICKSTART.md` | **NEW** - This quick start guide |

---

## Key Concepts

### Root App (Single Entry Point)

All GitOps configuration flows through `root-app`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
spec:
  source:
    repoURL: https://github.com/vietcgi/kubernetes-platform-stack
    path: argocd/config  # Everything synced from here
```

Push changes to `argocd/config/` → Committed to Git → ArgoCD auto-syncs

### Four Phases

```
Phase 1: Network (3 min) - CoreDNS ready
   ↓
Phase 2: ArgoCD (2 min) - ArgoCD ready to sync
   ↓
Phase 3: Bootstrap (10s) - Apply root-app to Git
   ↓
Phase 4: Monitor (20 min) - Verify cluster health
   ↓
Healthy Cluster Ready ✓
```

### Why 20 Minutes?

ArgoCD needs time to:
1. Sync namespaces (30s)
2. Install Cilium CNI (2-3 min)
3. Install infrastructure apps (2-3 min)
4. Deploy platform applications (5+ min)
5. Wait for all pods to be ready (5+ min)
6. Handle retries and reconciliation (remaining time)

Total: ~20 minutes ensures everything succeeds.

---

## Next Steps

1. ✅ **Run**: `bash deploy.sh`
2. ⏳ **Wait**: 25 minutes for health report
3. 🚀 **Deploy Apps**: Push changes to `argocd/applications/` or `argocd/applicationsets/`
4. 📊 **Monitor**: Use `kubectl get applications -n argocd -w`
5. 🔧 **Manage**: Update configs in Git, let ArgoCD sync automatically

---

## Support

**Full documentation**: See `HYBRID_GITOPS_ARCHITECTURE.md`

**Health check functions**: See `scripts/health-check.sh`

**Example applications**: Check `argocd/applications/` and `argocd/applicationsets/`
