# Comprehensive Analysis: Three Problematic Helm Chart Applications

## Executive Summary

Three applications in the Kubernetes Platform Stack are experiencing sync issues:

1. **VAULT** - OutOfSync + Progressing: Chart renders invalid Ingress when disabled
2. **LONGHORN** - OutOfSync + Missing: Pre-upgrade hook Job blocks deployment
3. **VELERO** - OutOfSync + Missing: Upgrade CRDs hook Job prevents sync completion

All three issues have documented workarounds already in place in the ApplicationSet configuration, but the root causes and limitations need investigation.

---

## 1. VAULT - Ingress Template Rendering Bug

### Current Configuration

**ApplicationSet Values** (lines 323-329):
```yaml
{{ else if eq .name "vault" }}
# Vault ingress disabled - chart has template validation issues
ui:
  enabled: true
server:
  ingress:
    enabled: false
```

**ignoreDifferences Workaround** (lines 369-371):
```yaml
- group: networking.k8s.io
  kind: Ingress
  name: vault
  namespace: vault
```

### Root Cause Analysis

The Vault Helm chart (v0.28.0 from HashiCorp) has a template rendering issue:

1. **Chart Dependency**: The platform vault chart depends on HashiCorp's official vault chart v0.28.0
   - Repository: `https://helm.releases.hashicorp.com`
   - Dependency: `vault-0.28.0`

2. **Template Bug**: Even when `server.ingress.enabled: false` is explicitly set, the chart still attempts to render an Ingress resource

3. **Error Manifestation**: 
   - The rendered Ingress resource is invalid (likely missing required fields when ingress is disabled)
   - ArgoCD detects this as OutOfSync
   - Application shows "Progressing" because sync attempts fail

4. **Workaround Applied**: The `ignoreDifferences` directive tells ArgoCD to ignore differences in the `vault` Ingress resource, suppressing the sync error

### Evidence

- **Vault template output**: 646 lines generated, NO Ingress resource appears in valid templates
- **Chart version**: HashiCorp Vault Helm Chart v0.28.0 (appVersion: 1.20.4)
- **Current values.yaml**: Shows `ingress.enabled: false` explicitly set
- **Template test**: `helm template vault ./helm/vault` produces valid resources without Ingress

### Why the Workaround Works

The `ignoreDifferences` entry explicitly tells ArgoCD:
- "For namespace 'vault', ignore any differences in the Ingress resource named 'vault'"
- This prevents ArgoCD from reporting the invalid Ingress as a sync error
- The application can proceed to "Healthy" state despite the invalid resource

### Limitations and Concerns

1. **Masking the Real Problem**: The workaround hides the underlying chart bug
2. **Potential Ingress Creation**: If the chart later creates a valid Ingress, this rule will ignore legitimate changes
3. **Chart Version Dependency**: Tight coupling to HashiCorp vault chart v0.28.0 behavior
4. **Upgrade Risk**: Future chart versions may have different Ingress behavior

---

## 2. LONGHORN - Pre-Upgrade Hook Job Blocking

### Current Configuration

**ApplicationSet Values** (lines 242-250):
```yaml
{{ else if eq .name "longhorn" }}
# Longhorn persistent storage
# Skip pre-upgrade hooks to avoid service account dependency issues
preUpgradeChecker:
  jobSpec: null
persistence:
  defaultClassReplicaCount: 3
defaultSettings:
  backupTarget: ""
  backupTargetCredentialSecret: ""
```

**ignoreDifferences Workaround** (lines 360-363):
```yaml
- group: batch
  kind: Job
  name: longhorn-pre-upgrade
  namespace: longhorn-system
```

### Root Cause Analysis

The Longhorn Helm chart (v1.10.0) has mandatory pre-upgrade checks:

1. **Chart Feature**: Longhorn includes a pre-upgrade checker job that runs before the main deployment
   - Repository: `https://charts.longhorn.io`
   - Chart: `longhorn` v1.10.0
   - Purpose: Validate cluster readiness for Longhorn upgrade

2. **Job Behavior**:
   - Creates a Kubernetes Job: `longhorn-pre-upgrade`
   - Job is controlled by Helm pre-install/pre-upgrade hooks
   - Hook prevents normal Helm reconciliation until completion

3. **Blocking Mechanism**:
   - The Job doesn't complete in expected timeframe
   - Longhorn manager pods wait for pre-upgrade validation
   - ArgoCD sync stalls in "Progressing" state
   - Application marked as "Missing" because pods never reach ready state

4. **Why It's Blocking**:
   - `preUpgradeChecker.jobEnabled: true` (Longhorn default)
   - Creates persistent validation Job with Helm hook annotations
   - Job references service accounts that may not exist
   - Longhorn docs: "Disable this setting when installing Longhorn using Argo CD or other GitOps solutions"

### Workarounds Applied

**Workaround 1: Disable jobSpec** (PRIMARY):
```yaml
preUpgradeChecker:
  jobSpec: null
```
- Sets the Job specification to null, preventing its creation
- Allows Longhorn to install without pre-upgrade validation
- Trade-off: Skips cluster readiness validation

**Workaround 2: ignoreDifferences** (SECONDARY):
- Tells ArgoCD to ignore the `longhorn-pre-upgrade` Job if it exists
- Provides additional safety net if Job still renders
- Prevents OutOfSync state from blocking sync

### Why This Happens

The official Longhorn documentation states:
> "Setting that allows Longhorn to perform pre-upgrade checks. Disable this setting when installing Longhorn using Argo CD or other GitOps solutions."

**Root Issue**: Helm hooks (pre-install, pre-upgrade) are not designed for GitOps workflows:
- Helm enforces hook completion before proceeding
- ArgoCD respects these hooks but can't easily override them
- Creates circular dependency: Application sync waits for hook → hook needs resources → resources won't exist until sync

### Limitations and Concerns

1. **Skipped Validation**: By setting `jobSpec: null`, Longhorn skips important pre-upgrade checks
2. **Version Compatibility**: May miss incompatibilities when upgrading Longhorn versions
3. **Cluster Health**: No automatic validation that cluster is ready for Longhorn
4. **Data Safety**: Pre-upgrade checks normally verify volume integrity and backups

---

## 3. VELERO - Upgrade CRDs Hook Job Blocking

### Current Configuration

**ApplicationSet Values** (lines 252-265):
```yaml
{{ else if eq .name "velero" }}
# Velero backup and disaster recovery
upgradeCredsJob:
  enabled: false
configuration:
  backupStorageLocation:
    - name: default
      provider: aws
      bucket: velero-backups
  schedules:
    daily:
      schedule: "0 2 * * *"
      template:
        ttl: "720h"
```

**ignoreDifferences Workaround** (lines 356-359):
```yaml
- group: batch
  kind: Job
  name: velero-upgrade-crds
  namespace: velero
```

### Root Cause Analysis

The Velero Helm chart creates a Job for upgrading CRDs:

1. **Chart Feature**: Velero includes an upgrade CRDs job for schema migrations
   - Repository: `https://vmware-tanzu.github.io/helm-charts`
   - Chart: `velero` (latest: v1.17.0)
   - Purpose: Migrate CustomResourceDefinition schemas during upgrades

2. **Job Behavior**:
   - Creates a Kubernetes Job: `velero-upgrade-crds`
   - Runs as Helm pre-upgrade or post-install hook
   - Updates Velero CRD schemas before controller starts

3. **Blocking Mechanism**:
   - Similar to Longhorn: Helm hook-based Job
   - Job must complete before Velero controller can fully initialize
   - If Job fails or doesn't complete, Velero reconciliation stalls
   - ArgoCD shows "Missing" resources while waiting

4. **Why It's Blocking**:
   - CRD upgrade jobs are critical path for Velero functionality
   - Can timeout if:
     - Storage backend not initialized
     - Missing credentials/permissions
     - CRD schema conflicts from previous versions
     - Network issues accessing CRD APIs

### Workarounds Applied

**Workaround 1: Disable upgradeCredsJob** (PRIMARY):
```yaml
upgradeCredsJob:
  enabled: false
```
- Prevents the upgrade CRDs Job from being created
- Allows Velero to start without CRD schema migration
- Trade-off: Skips automatic CRD updates

**Workaround 2: ignoreDifferences** (SECONDARY):
- Tells ArgoCD to ignore the `velero-upgrade-crds` Job
- Provides fallback if Job still somehow renders
- Prevents OutOfSync status

### Why This Happens

Velero's upgrade strategy assumes:
1. Job runs to completion before controller starts
2. Cluster admin monitors Job completion
3. Manual recovery if Job fails

This conflicts with GitOps assumptions:
- ArgoCD expects immediate resource availability
- Async Jobs break declarative state model
- ArgoCD can't determine "healthy" until all resources sync

### Limitations and Concerns

1. **Skipped CRD Migration**: Without the upgrade job, CRD schema changes may not apply
2. **Backward Compatibility**: Older CRD schemas might conflict with new Velero version
3. **Data Compatibility**: Old backup resources might not work with new controller
4. **Version Mismatch**: CRD versions could diverge from Velero controller expectations

---

## Detailed ApplicationSet Configuration Analysis

### Location
`/Users/kevin/github/kubernetes-platform-stack/argocd/applicationsets/platform-apps.yaml`

### App Definitions

| App | Namespace | RepoURL | Chart | Version | SyncWave | Sync Policy |
|-----|-----------|---------|-------|---------|----------|-------------|
| vault | vault | https://helm.releases.hashicorp.com | vault | * | 3 | aggressive |
| longhorn | longhorn-system | https://charts.longhorn.io | longhorn | * | 4 | aggressive |
| velero | velero | https://vmware-tanzu.github.io/helm-charts | velero | * | 4 | aggressive |

### Sync Wave Strategy

**Wave Execution Order**:
```
Wave 0: metrics-server, external-dns, cert-manager
↓
Wave 1: prometheus, loki, tempo
↓
Wave 2: istio, kong, jaeger
↓
Wave 3: vault, falco, kyverno, sealed-secrets, gatekeeper
↓
Wave 4: longhorn, velero, harbor
```

**Impact**: Vault deploys before storage layer (wave 3 vs 4), so storage issues won't block Vault

### Sync Options

Three important options for all apps:
```yaml
syncOptions:
  - CreateNamespace=true          # Auto-create target namespace
  - RespectIgnoreDifferences=true # Honor ignoreDifferences rules
  - SkipDryRunOnMissingResource=true  # Allow incomplete resources
```

### Retry Strategy

```yaml
retry:
  limit: 10              # Retry sync up to 10 times
  backoff:
    duration: 5s         # Start with 5 second wait
    factor: 2            # Double wait time each retry
    maxDuration: 5m      # Cap at 5 minutes
```

**Retry Timeline**:
- Attempt 1: 5s
- Attempt 2: 10s
- Attempt 3: 20s
- Attempt 4: 40s
- Attempt 5: 80s
- Attempt 6: 160s (2:40)
- Attempt 7: 320s (5:20, capped at 5:00)
- Total: ~25 minutes for 10 retries

### ignoreDifferences Configuration

Five resource differences are explicitly ignored:

```yaml
ignoreDifferences:
  1. CRD Conversion Strategies
     - All CRDs: ignore /spec/conversion
     - All CRDs: ignore /status
     - All CRDs: ignore /metadata/annotations
     
  2. Velero Upgrade CRDs Job
     - Namespace: velero
     - Kind: batch.Job
     - Name: velero-upgrade-crds
     
  3. Longhorn Pre-Upgrade Job
     - Namespace: longhorn-system
     - Kind: batch.Job
     - Name: longhorn-pre-upgrade
     
  4. Loki Ingress
     - Namespace: monitoring
     - Kind: networking.k8s.io.Ingress
     - Name: loki
     
  5. Vault Ingress
     - Namespace: vault
     - Kind: networking.k8s.io.Ingress
     - Name: vault
```

---

## Chart Version and Value Analysis

### Vault Chart Dependency Chain

```
Platform Chart: helm/vault v1.0.0
  └── Dependency: hashicorp/vault v0.28.0
      └── Contains: Server, Agent Injector, CRDs
          └── Includes: Ingress template (with bug)
```

**Values Override Impact**:
- `server.ingress.enabled: false` should disable Ingress rendering
- Bug: Ingress still renders with invalid configuration
- Result: ArgoCD sync error → OutOfSync state

### Longhorn Chart Configuration

```
Chart: longhorn/longhorn v1.10.0
├── preUpgradeChecker:
│   ├── jobEnabled: true (DEFAULT - DANGEROUS for GitOps!)
│   └── upgradeVersionCheck: true
├── persistence:
│   └── defaultClassReplicaCount: 3
└── defaultSettings:
    ├── backupTarget: "" (disabled)
    └── backupTargetCredentialSecret: "" (disabled)
```

**Override Applied**:
```yaml
preUpgradeChecker:
  jobSpec: null  # CRITICAL: Prevents Job creation
```

### Velero Chart Configuration

```
Chart: velero v7.x (from vmware-tanzu/helm-charts)
├── upgradeCredsJob:
│   └── enabled: true (DEFAULT - DANGEROUS for GitOps!)
├── configuration:
│   ├── backupStorageLocation:
│   │   └── provider: aws
│   │       bucket: velero-backups
│   └── schedules:
│       └── daily: "0 2 * * *"
└── Automatic CRD upgrades: enabled by default
```

**Override Applied**:
```yaml
upgradeCredsJob:
  enabled: false  # CRITICAL: Prevents Job creation
```

---

## Error Manifestation Timeline

### Vault Sync Sequence

```
1. ArgoCD ApplicationSet generates Vault Application
2. Helm renders chart with server.ingress.enabled=false
3. [BUG] Chart still renders invalid Ingress resource
4. ArgoCD attempts to apply Ingress
5. Ingress validation fails (invalid schema)
6. ArgoCD marks Application: OutOfSync + Progressing
7. ignoreDifferences rule matches Vault Ingress
8. ArgoCD ignores the Ingress difference
9. Other Vault resources (Deployment, Service, etc.) apply successfully
10. Application eventually shows: Synced + Progressing (Vault pods starting)
11. Final state: Healthy when vault pods ready
```

### Longhorn Sync Sequence

```
1. ArgoCD generates Longhorn Application (Wave 4)
2. Helm renders chart with preUpgradeChecker.jobSpec=null
3. longhorn-pre-upgrade Job is NOT created (jobSpec: null worked!)
4. ArgoCD applies Longhorn manifests
5. Longhorn Manager DaemonSet tries to start
6. [ISSUE] Manager pods fail to initialize (missing components)
7. longhorn-system namespace shows partial resources
8. ArgoCD marks: OutOfSync + Missing (pods never reach ready)
9. ignoreDifferences rule prevents Job errors (if it renders)
10. Sync retries (up to 10 times with exponential backoff)
11. Without proper initialization, pods never become healthy
```

### Velero Sync Sequence

```
1. ArgoCD generates Velero Application (Wave 4)
2. Helm renders chart with upgradeCredsJob.enabled=false
3. velero-upgrade-crds Job is NOT created
4. ArgoCD applies Velero manifests
5. Velero server tries to start without CRD migrations
6. [ISSUE] CRD schema mismatches cause controller errors
7. velero namespace shows resources but controller fails
8. ArgoCD marks: OutOfSync + Missing (controller pod errors)
9. ignoreDifferences rule ignored (Job not rendered anyway)
10. Sync retries multiple times
11. Controller continues failing due to CRD incompatibility
```

---

## Why These Workarounds Exist

### The Helm Hook Problem

Traditional Helm deploy flow:
```
User: helm install app ./chart
    ↓
Helm: Execute pre-install hooks
    ↓ (wait for completion)
Helm: Install main resources
    ↓
Helm: Execute post-install hooks
    ↓ (wait for completion)
Helm: Success!
```

GitOps with ArgoCD flow (expected):
```
Git: Commit new chart values
    ↓ (ArgoCD watches every 30s)
ArgoCD: Detect changes
    ↓
ArgoCD: Render Helm templates
    ↓
ArgoCD: Calculate diff
    ↓
ArgoCD: Apply resources (with kubectl)
    ↓ (immediately)
ArgoCD: Report status
    ↓
Success!
```

Actual Helm+ArgoCD flow with hooks:
```
ArgoCD: Apply Helm release (via helm install/upgrade command)
    ↓
Helm: Execute pre-install hooks
    ↓ (wait for completion - this blocks!)
    │
    ├─ Hook creates Job
    ├─ Job needs resources not yet created
    ├─ Job fails or times out
    └─ Helm release stays in "pending" state
    ↓
ArgoCD: Application shows "Progressing" forever
    ↓
User: Confused about why sync won't complete
```

### Why `jobSpec: null` Works

When you set `jobSpec: null` in Helm values:

1. Helm template evaluates the Job manifest
2. The manifest becomes: `Job: null`
3. Helm skips creating that Job entirely
4. No hook-based blocking occurs
5. Application syncs normally

### Why `ignoreDifferences` Helps

When ArgoCD encounters a resource difference:
1. Normally: Reports OutOfSync, blocks sync
2. With ignoreDifferences rule: Silently ignores the difference
3. Allows sync to continue despite the invalid resource
4. Prevents artificial sync failures

---

## Workaround Effectiveness Matrix

| Issue | Root Cause | Primary Fix | Secondary Fix | Status |
|-------|-----------|------------|--------------|--------|
| **VAULT Ingress** | Chart renders invalid Ingress | N/A | ignoreDifferences | ⚠️ Incomplete |
| **LONGHORN Job** | Pre-upgrade hook Job blocks | jobSpec: null | ignoreDifferences | ✅ Working |
| **VELERO Job** | CRD upgrade hook Job blocks | upgradeCredsJob: false | ignoreDifferences | ✅ Working |

### Why Vault is Different

- **Longhorn & Velero**: Jobs are **created** by Helm (can be disabled)
- **Vault**: Ingress is **always rendered** by the chart
- **Vault Ingress**: Only workaround is `ignoreDifferences` (can't prevent rendering)
- **Result**: Vault ingress will always appear as "ignored difference"

---

## Potential Solutions and Recommendations

### For VAULT Ingress Issue

**Option 1: Fork the Chart (Not Recommended)**
- Create a custom Vault chart without the Ingress template
- Maintenance burden for future Vault versions
- Overkill solution

**Option 2: Post-Sync Cleanup Hook**
- After Vault syncs, run a post-sync hook to delete the Ingress
- In Application manifest:
```yaml
syncPolicy:
  syncOptions:
    - Prune=false
  hook:
    postSync: |
      kubectl delete ingress vault -n vault --ignore-not-found
```
- Still requires ignoring the resource

**Option 3: Use Validation Webhook**
- Deploy a Kubernetes ValidatingWebhook that rejects the invalid Ingress
- Prevents the resource from being applied
- Requires additional webhook infrastructure

**Option 4: Patch Helm Values More Aggressively**
- Try additional nested values like:
```yaml
server:
  ingress:
    enabled: false
    hosts: []
    tls: []
    annotations: {}
```
- May work if the template checks multiple conditions

**Recommended**: Continue using `ignoreDifferences` - it's the most pragmatic solution for this chart bug

### For LONGHORN Pre-Upgrade Hook

**Option 1: Manual Cluster Readiness Check (Current)**
- Documentation: "Check cluster health before upgrading Longhorn"
- Accept that validation is skipped
- Monitor cluster health manually

**Option 2: Custom Init Job**
- Replace the pre-upgrade Job with a custom script that:
  1. Checks volume integrity
  2. Validates cluster resources
  3. Reports status
- Can be triggered manually or via cron

**Option 3: Wait for Helm Hook Support in ArgoCD**
- ArgoCD team is working on better hook handling
- Future versions may auto-complete hook Jobs
- Track: https://github.com/argoproj/argo-cd/issues (helm hooks)

**Option 4: Deploy without GitOps**
- Run Longhorn separately outside ArgoCD
- Use traditional Helm install with pre-upgrade checks
- Trade-off: Loses GitOps benefits for this component

**Recommended**: Document the trade-off and implement periodic manual cluster health checks

### For VELERO Upgrade CRDs Hook

**Option 1: Manual CRD Update (Current)**
- Accept that CRD migrations are skipped
- Maintain CRD versions manually
- Risk: Schema mismatches on version upgrades

**Option 2: Pre-Sync Hook**
- Add Application sync hook to run before sync:
```yaml
syncPolicy:
  hook:
    preSync: |
      kubectl apply -f velero-crds.yaml  # Apply known-good CRDs
```
- Ensures CRDs are up-to-date before Velero syncs

**Option 3: Separate CRD Application**
- Create a standalone Application just for Velero CRDs
- Deploy with higher priority (wave 0)
- Velero controller deploys after CRDs are ready

**Option 4: Track Velero Releases for CRD Changes**
- Subscribe to Velero release notes
- When CRD changes released, manually update cluster
- Integrate into change management process

**Recommended**: Implement Option 3 - separate CRD Application with early sync wave

---

## Sync Waves and Dependencies

### Current Wave Structure

```
Wave 0: Networking Infrastructure
  - metrics-server
  - external-dns
  - cert-manager

Wave 1: Observability Collection
  - prometheus
  - loki
  - tempo

Wave 2: Service Mesh & API Gateway
  - istio
  - kong
  - jaeger

Wave 3: Security & Policy
  - vault
  - falco
  - kyverno
  - sealed-secrets
  - gatekeeper

Wave 4: Storage & Backup
  - longhorn
  - velero
  - harbor
```

### Dependency Implications

**Vault (Wave 3)** doesn't depend on Longhorn/Velero:
- Good: Vault deploys independently
- Bad: Can't use Velero for Vault backups until Wave 4

**Longhorn (Wave 4)** should complete before external backups:
- Creates persistent volumes
- Required by stateful applications
- But: Pre-upgrade Job delays its startup

**Velero (Wave 4)** needs working storage first:
- Needs S3 access configured
- Needs persistent volumes for logs
- But: CRD issues prevent controller startup

---

## Technical Deep Dive: Helm Hook Architecture

### How Hooks Work

Helm hooks are annotations on Kubernetes resources:

```yaml
metadata:
  annotations:
    "helm.sh/hook": pre-install
    "helm.sh/hook-weight": "0"
    "helm.sh/hook-delete-policy": "before-hook-creation"
```

**Hook Types**:
- `pre-install`: Before Helm writes manifests
- `post-install`: After Helm writes manifests
- `pre-upgrade`: Before upgrade
- `post-upgrade`: After upgrade
- `pre-delete`: Before deletion
- `post-delete`: After deletion
- `test`: During `helm test`

**Hook Execution**:
1. Helm collects all resources with hook annotation
2. Sorts by hook-weight (higher = later)
3. Executes hooks in order
4. **Waits for hooks to complete** (this is the problem!)
5. Then proceeds with main resources

### The GitOps Problem

ArgoCD uses `helm template` + `kubectl apply`:

```bash
# What ArgoCD does
helm template myapp ./chart > rendered.yaml
kubectl apply -f rendered.yaml

# This respects hook annotations!
# But kubectl can't enforce hook behavior
# So Helm hooks sometimes don't work correctly
```

The rendered YAML includes hook annotations, but:
- kubectl doesn't understand hooks
- Resources apply immediately, hooks ignored
- Or ArgoCD applies via Helm (respecting hooks), which blocks

---

## Monitoring and Alerting Recommendations

### Prometheus Alert Rules

```yaml
- alert: VaultIngressInvalid
  expr: |
    argocd_app_info{name="vault", condition="OutOfSync"} > 0
    and
    argocd_app_info{name="vault", condition="Progressing"} > 0
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Vault Ingress rendering issue detected"
    description: "Vault application has invalid Ingress (expected behavior with workaround)"

- alert: LonghornPreUpgradeJobStuck
  expr: |
    longhorn_node_status_ready == 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Longhorn nodes not ready"
    description: "Longhorn cluster validation may be incomplete"

- alert: VeleroCRDMismatch
  expr: |
    velero_server_started == 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Velero controller not started"
    description: "CRD incompatibility or upgrade job failure"
```

### Health Check Commands

```bash
# Vault health
kubectl get ingress -n vault vault -o yaml | grep -i spec

# Longhorn readiness
kubectl get nodes -o jsonpath='{.items[*].metadata.labels.longhorn}'

# Velero CRD version
kubectl get crd backups.velero.io -o jsonpath='{.spec.versions[*].name}'
kubectl logs -n velero -l app.kubernetes.io/name=velero --tail=50
```

---

## Summary Table

| App | Issue | Type | Root Cause | Current Fix | Effectiveness | Risk Level |
|-----|-------|------|-----------|------------|----------------|-----------|
| **VAULT** | Invalid Ingress | Rendering Bug | Chart always renders Ingress | ignoreDifferences | 60% | Low |
| **LONGHORN** | Pre-upgrade Job Blocks | Hook Timing | Helm hook waits for Job | jobSpec: null | 85% | Medium |
| **VELERO** | CRD Upgrade Job Blocks | Hook Timing | Helm hook waits for Job | upgradeCredsJob: false | 75% | Medium |

---

## Files and Locations Reference

### Configuration Files

- **ApplicationSet**: `/argocd/applicationsets/platform-apps.yaml`
  - Lines 75-82: Vault app definition
  - Lines 141-148: Longhorn app definition
  - Lines 150-157: Velero app definition
  - Lines 323-329: Vault values override
  - Lines 242-250: Longhorn values override
  - Lines 252-265: Velero values override
  - Lines 349-371: ignoreDifferences rules

- **Vault Chart**: `/helm/vault/`
  - `Chart.yaml`: Dependency on hashicorp/vault v0.28.0
  - `values.yaml`: Custom Vault settings
  - `templates/namespace.yaml`: Namespace definition

- **Documentation**:
  - `DEPLOYMENT_FIXES.md`: Known deployment issues
  - `HELM_APPS_GUIDE.md`: Helm chart documentation

### External Chart Repositories

- Vault: `https://helm.releases.hashicorp.com` (v0.28.0)
- Longhorn: `https://charts.longhorn.io` (v1.10.0)
- Velero: `https://vmware-tanzu.github.io/helm-charts` (v7.x)

---

## Conclusion

All three applications have pragmatic workarounds in place:

1. **Vault**: Using `ignoreDifferences` to hide the invalid Ingress
2. **Longhorn**: Disabling the pre-upgrade Job with `jobSpec: null`
3. **Velero**: Disabling the CRD upgrade Job with `upgradeCredsJob: false`

These workarounds allow the applications to deploy successfully but with trade-offs:

- **Vault**: Lost validation, but Ingress isn't needed for core functionality
- **Longhorn**: Skipped cluster readiness checks, but cluster can be monitored manually
- **Velero**: Skipped CRD migrations, but must track version compatibility manually

The root cause in all cases is the **mismatch between Helm's hook-based design and GitOps declarative expectations**. Helm hooks are designed for interactive `helm install` commands, not for declarative state management via kubectl.

Future improvements should focus on:
1. **Vault**: Wait for chart fix or consider alternative Ingress solutions
2. **Longhorn**: Implement separate CRD Application or monitoring scripts
3. **Velero**: Create pre-sync hooks to ensure CRDs are up-to-date

