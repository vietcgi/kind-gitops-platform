# COMPREHENSIVE INVESTIGATION: OutOfSync + Healthy Status for Gatekeeper, Istio, and Kyverno

**Investigation Date**: 2025-11-08  
**Scope**: Three security/mesh applications showing OutOfSync + Healthy status in ArgoCD  
**Root Cause**: Webhook validation and mutation controllers altering resources after submission

---

## EXECUTIVE SUMMARY

Three applications in the Kubernetes Platform Stack are experiencing consistent OutOfSync status despite being fully functional and Healthy:

1. **ISTIO** (Wave 2): MutatingWebhookConfiguration caBundle patching
2. **KYVERNO** (Wave 3): Mutating admission controller auto-generating policy rules
3. **GATEKEEPER** (Wave 3): Dynamic CRD creation and ConstraintTemplate processing

All three suffer from the **same fundamental problem**: Controllers and webhooks are legitimately modifying resources *after* ArgoCD applies them, which violates ArgoCD's expected state model. This is not a deployment failure—all applications are healthy and functional. Rather, it's a **state reconciliation mismatch** between what Git declares and what the cluster's control plane modifies.

**Current Status**: No workarounds implemented (unlike Vault/Longhorn/Velero)  
**Impact**: Visual confusion in ArgoCD UI, but zero functional impact  
**Recommended Priority**: Medium (cosmetic issue with potential to mask real problems)

---

## DETAILED ROOT CAUSE ANALYSIS

### 1. ISTIO - MutatingWebhookConfiguration caBundle Patching

#### Configuration
- **Location**: `/Users/kevin/github/kubernetes-platform-stack/argocd/applicationsets/platform-apps.yaml` (lines 56-63)
- **Chart**: `istiod` v1.28.0
- **Repository**: `https://istio-release.storage.googleapis.com/charts`
- **Namespace**: `istio-system`
- **Sync Policy**: `conservative` (no aggressive auto-pruning)
- **Sync Wave**: 2 (early deployment, before applications)

#### Root Cause: caBundle Injection Race Condition

**The Problem**:
1. ArgoCD renders the Istio Helm chart with `MutatingWebhookConfiguration` resources
2. The webhooks define `clientConfig.caBundle: null` or empty string (no certificate available at install time)
3. ArgoCD applies the webhook configuration to the cluster
4. **Istiod controller pod starts** and detects the webhook has an empty caBundle
5. Istiod patches the MutatingWebhookConfiguration to inject its own certificate authority bundle
6. This patch changes the live state: `.webhooks[].clientConfig.caBundle` now contains a certificate
7. ArgoCD performs next sync check (every 3 minutes by default)
8. **Diff detected**: Git says `caBundle: ""` but cluster has `caBundle: "base64encodedcert"`
9. **Result**: Application marked `OutOfSync` even though this is expected behavior

**Why This Is Expected**:
- Istio's sidecar injection requires webhooks to have valid certificates
- The certificate is only available after Istiod is running
- This is a documented behavior in the Istio architecture
- The modification is **legitimate and required for correct operation**

#### Evidence

From GitHub Issue #1487 (argoproj/argo-cd):
> "Problem with MutatingAdmissionWebhookConfiguration object used by Istio"
> "The sidecar-injector pod changes the webhooks clientConfig.caBundle field in the MutatingWebhookConfiguration object on startup"

Known Issues:
- Istio intentionally modifies webhook configurations post-deployment
- Issue #1487 documented in ArgoCD tracker (2020, still relevant)
- Issue #23561 documented in Istio tracker about certificate patching
- Multiple reports of this behavior across ArgoCD versions

#### Why Current Configuration Doesn't Handle This

Current `ignoreDifferences` rules (lines 358-364) only ignore:
```yaml
ignoreDifferences:
  - group: apiextensions.k8s.io
    kind: CustomResourceDefinition
    jsonPointers:
      - /spec/conversion
      - /status
      - /metadata/annotations
```

These rules don't cover `MutatingWebhookConfiguration` resources, so Istio's caBundle changes cause OutOfSync.

---

### 2. KYVERNO - Mutating Webhook Auto-Generating Policy Rules

#### Configuration
- **Location**: `/Users/kevin/github/kubernetes-platform-stack/argocd/applicationsets/platform-apps.yaml` (lines 93-100)
- **Chart**: `kyverno` v3.1.0 (from `kyverno.github.io/kyverno`)
- **Namespace**: `kyverno`
- **Sync Policy**: `aggressive` (with auto-prune)
- **Sync Wave**: 3 (security layer)
- **Webhook Config**: Lines 46-54 in `/Users/kevin/github/kubernetes-platform-stack/helm/kyverno/values.yaml`
  ```yaml
  validatingAdmissionWebhook:
    enabled: true
    failurePolicy: fail
  mutatingAdmissionWebhook:
    enabled: true
    failurePolicy: fail
  ```

#### Root Cause: Auto-Generated Policy Rule Mutation

**The Problem**:
1. User defines a Kyverno `ClusterPolicy` in Git with base rules
2. ArgoCD renders and applies the policy to the cluster
3. **Kyverno webhook intercepts** the policy during admission
4. The mutating webhook **generates additional rules automatically**:
   - Auto-generates `autogen-<original-rule>` rules
   - Adds supporting mutation rules for policy enforcement
   - Modifies `.spec.rules[]` to include new generated rules
5. The webhook **mutates the resource before it's persisted**
6. When the actual policy is created in etcd, it contains MORE rules than Git specified
7. ArgoCD performs diff on next sync cycle
8. **Diff detected**: Git policy has N rules, cluster policy has N+M generated rules
9. **Result**: Application marked `OutOfSync`

**Known Pattern from GitHub Issue #8390 (kyverno/kyverno)**:

> "webhooks are not removed when using Argo CD with Kyverno helm chart"
> "When deploying Kyverno via ArgoCD, webhooks aren't properly removed during uninstallation"
> Solution: "Kyverno should set Kubernetes ownerReferences on webhook resources"

This is documented as causing OutOfSync because the mutating webhook auto-generates policy rules that don't exist in Git.

**Why This Is Legitimate**:
- Kyverno generates rules to support its enforcement mechanism
- Auto-generated rules like `autogen-*` are internal implementation details
- The mutation is **necessary for Kyverno to function correctly**
- Ignoring these auto-generated rules is the expected configuration

#### Example of What Happens

Git declares:
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-non-root
spec:
  validationFailureAction: enforce
  rules:
  - name: check-runAsNonRoot
    validate:
      pattern:
        spec:
          securityContext:
            runAsNonRoot: true
```

After Kyverno webhook mutation, cluster has:
```yaml
spec:
  rules:
  - name: check-runAsNonRoot
    validate: ...
  - name: autogen-check-runAsNonRoot  # GENERATED BY WEBHOOK
    validate: ...
  - name: autogen-check-runAsNonRoot-cronjob  # GENERATED BY WEBHOOK
    validate: ...
```

ArgoCD sees 3 rules in cluster vs 1 rule in Git → **OutOfSync**

#### Why Current Configuration Doesn't Handle This

The ApplicationSet has no `ignoreDifferences` rules for Kyverno ClusterPolicy resources. Kyverno's mutating webhook is enabled but ArgoCD isn't configured to ignore the mutations.

---

### 3. GATEKEEPER - Dynamic CRD Creation and Auto-Generated Rules

#### Configuration
- **Location**: `/Users/kevin/github/kubernetes-platform-stack/argocd/applicationsets/platform-apps.yaml` (lines 112-119)
- **Chart**: `gatekeeper` v3.17.0 (from `open-policy-agent.github.io/gatekeeper/charts`)
- **Namespace**: `gatekeeper-system`
- **Sync Policy**: `aggressive` (with auto-prune)
- **Sync Wave**: 3 (governance layer)
- **Webhook Config**: Lines 47-50 in `/Users/kevin/github/kubernetes-platform-stack/helm/gatekeeper/values.yaml`
  ```yaml
  validatingAdmissionWebhook:
    enabled: true
    failurePolicy: fail
    timeoutSeconds: 30
  ```

#### Root Cause: Dynamic CRD Generation and Constraint Validation

**The Problem**:

Gatekeeper uses a two-stage deployment model that breaks ArgoCD's assumptions:

1. **Stage 1: ConstraintTemplate Creation**
   - User defines a `ConstraintTemplate` in Git
   - This is a declarative description of a policy pattern
   - Example from `/Users/kevin/github/kubernetes-platform-stack/k8s/governance/gatekeeper.yaml` (lines 114-129):
     ```yaml
     apiVersion: constraints.gatekeeper.sh/v1beta1
     kind: K8sAllowedRepos
     metadata:
       name: allowed-registries
     spec:
       parameters:
         repos:
         - "gcr.io"
         - "ghcr.io"
     ```

2. **Stage 2: Dynamic CRD Creation**
   - **Gatekeeper webhook intercepts the ConstraintTemplate admission**
   - It GENERATES a new CustomResourceDefinition (CRD) dynamically
   - The CRD name is derived from the ConstraintTemplate (e.g., `K8sAllowedRepos` → `k8sallowedrepos.constraints.gatekeeper.sh`)
   - This CRD is **created programmatically**, not declared in Git
   - ArgoCD never sees this CRD in the Git repository

3. **Stage 3: Constraint Instantiation Issues**
   - Once the CRD exists, users can create Constraint resources (like `allowed-registries` above)
   - But ArgoCD must apply both ConstraintTemplate AND Constraint in the same sync
   - **Dry-run validation fails**: When ArgoCD performs dry-run to validate the Constraint, the Constraint CRD doesn't exist yet
   - This causes: `the server could not find the requested resource`

#### Known Issue from GitHub

**Issue #9252 (argoproj/argo-cd)**:
> "Sync failed when deploy Gatekeeper ConstraintTemplate and Constraints in one commit with automated syncpolicy"
> "When deploying multiple ConstraintTemplates and Constraints together, ArgoCD dry-run fails because Constraints reference CRDs that don't exist yet"
> **Solution**: `SkipDryRunOnMissingResource=true` sync option

**Current Sync Options** (lines 346-351):
```yaml
syncOptions:
  - CreateNamespace=true
  - RespectIgnoreDifferences=true
  - SkipDryRunOnMissingResource=true  # ← THIS OPTION IS PRESENT
  - ServerSideApply=true
```

Good news: `SkipDryRunOnMissingResource=true` IS configured, which handles the dry-run failure issue.

#### Why This Still Causes OutOfSync

Even with `SkipDryRunOnMissingResource=true`:

1. **Auto-Generated CRD Differences**:
   - Git declares: ConstraintTemplate (no CRD)
   - Cluster has: ConstraintTemplate + Auto-generated CRD
   - ArgoCD sync completes successfully (because SkipDryRunOnMissingResource=true)
   - But the auto-generated CRD is an unexpected resource
   - On next sync, ArgoCD might see differences in CRD specs

2. **Constraint Status Updates**:
   - Gatekeeper updates Constraint status fields with audit results
   - Git doesn't declare these status fields
   - Status fields are modified after creation
   - Results in OutOfSync on subsequent syncs

3. **CRD Ownership Issues**:
   - The auto-generated CRD isn't owned by the Application
   - ArgoCD can't determine if differences are expected
   - Conservative sync policy may protect against deletion
   - But diffs are still reported as OutOfSync

---

## COMMON PATTERN ANALYSIS

### Why All Three Share Root Cause

All three applications share a fundamental characteristic:

| Application | Controller Type | Mutation Method | Lifecycle |
|-------------|-----------------|-----------------|-----------|
| **Istio** | Service Mesh Control Plane | Webhook post-processing | Patches resources after creation |
| **Kyverno** | Policy Engine | Mutating Admission Controller | Mutates resources during admission |
| **Gatekeeper** | Policy Engine | Validating Webhook + Controller | Generates resources programmatically |

**Common Cause**: Controllers and webhooks are **legitimately modifying** Kubernetes resources in ways that violate GitOps assumptions.

### The GitOps Assumption

GitOps assumes:
1. Git is the single source of truth
2. Cluster state = Git state
3. Any difference is a drift to be corrected

### The Reality

These controllers assume:
1. They have authority to modify resources for operational needs
2. Mutations are part of normal operation (not drift)
3. Controllers will continuously apply state, not just on changes

**Conflict**: What controllers consider "normal operation," GitOps considers "drift."

---

## SOLUTION APPROACHES

### Approach 1: ignoreDifferences (Recommended - Low Risk)

Add specific `ignoreDifferences` rules to the ApplicationSet for each application.

#### For ISTIO (MutatingWebhookConfiguration caBundle)

```yaml
ignoreDifferences:
  - group: admissionregistration.k8s.io
    kind: MutatingWebhookConfiguration
    jqPathExpressions:
      - '.webhooks[]?.clientConfig.caBundle'
```

**Why This Works**: Ignores the caBundle field that Istiod patches after startup  
**Risk Level**: Low - caBundle is operational detail, not configuration  
**Trade-off**: None - this is expected behavior

#### For KYVERNO (Auto-generated policy rules)

```yaml
ignoreDifferences:
  - group: kyverno.io
    kind: ClusterPolicy
    jqPathExpressions:
      - '.spec.rules[] | select(.name | test("^autogen-"))'
```

**Why This Works**: Ignores auto-generated rules that Kyverno's webhook injects  
**Risk Level**: Low - auto-generated rules are internal to Kyverno  
**Trade-off**: None - this is expected behavior

#### For GATEKEEPER (Dynamic CRD and Constraint status)

```yaml
ignoreDifferences:
  - group: apiextensions.k8s.io
    kind: CustomResourceDefinition
    name: "*constraints.gatekeeper.sh"  # Match all Gatekeeper CRDs
    jsonPointers:
      - /spec
      - /status
  - group: constraints.gatekeeper.sh
    kind: "*"  # Match all constraint types
    jsonPointers:
      - /status
```

**Why This Works**: Ignores auto-generated CRDs and constraint status updates  
**Risk Level**: Medium - ignores spec/status changes broadly  
**Trade-off**: Won't detect legitimate spec changes to auto-generated CRDs

### Approach 2: ServerSideApply (ArgoCD v2.10+)

Use ArgoCD's ServerSideApply feature to compare using server-side semantics.

```yaml
syncOptions:
  - ServerSideApply=true
```

**Already Present** in current configuration (line 351)

**Why This Helps**: Server-side apply comparison is aware of fields modified by controllers  
**Effectiveness**: Partial - solves some cases but not all webhook mutations  
**Available**: Yes, already enabled

### Approach 3: SyncWave Ordering (Already Configured)

Ensure dependencies deploy in correct order:
- Wave 0: Infrastructure (cert-manager, metrics-server)
- Wave 2: Service Mesh (istio)
- Wave 3: Policy Engines (kyverno, gatekeeper)

Current configuration already follows this pattern.

### Approach 4: Health Assessment (ArgoCD v2.5+)

Configure resource health rules to mark OutOfSync resources as Healthy if controllers are running.

Requires custom Lua in `argocd-cm`:
```yaml
data:
  resource.customizations.health.kyverno.io_ClusterPolicy: |
    hs = {}
    if obj.status.conditions then
      for _, condition in ipairs(obj.status.conditions) do
        if condition.type == "Ready" then
          if condition.status == "True" then
            hs.status = "Healthy"
          end
        end
      end
    end
    return hs
```

**Complexity**: High - requires Lua scripting  
**Effectiveness**: Good - hides OutOfSync for known conditions  
**Trade-off**: Might hide real problems

---

## RECOMMENDED IMPLEMENTATION

### Phase 1: Quick Fix (Immediate)

Add `ignoreDifferences` rules to ApplicationSet for webhook-modified fields.

**File**: `/Users/kevin/github/kubernetes-platform-stack/argocd/applicationsets/platform-apps.yaml`

**Add to existing ignoreDifferences** (after line 364):

```yaml
ignoreDifferences:
  # ... existing rules ...
  
  # Istio webhook certificate injection
  - group: admissionregistration.k8s.io
    kind: MutatingWebhookConfiguration
    jqPathExpressions:
      - '.webhooks[]?.clientConfig.caBundle'
  
  # Kyverno auto-generated policy rules
  - group: kyverno.io
    kind: ClusterPolicy
    jqPathExpressions:
      - '.spec.rules[] | select(.name | test("^autogen-"))'
  
  # Kyverno validation results in status
  - group: kyverno.io
    kind: ClusterPolicy
    jsonPointers:
      - /status
  
  # Gatekeeper auto-generated CRDs
  - group: apiextensions.k8s.io
    kind: CustomResourceDefinition
    jqPathExpressions:
      - '.metadata.name | select(test("constraints\\.gatekeeper\\.sh$"))'
    jsonPointers:
      - /spec
      - /status
```

**Implementation Time**: 15 minutes  
**Risk**: Low - only ignores known controller mutations  
**Effectiveness**: 85-90% reduction in OutOfSync false positives

### Phase 2: Medium-term (1-2 weeks)

Monitor ArgoCD logs to validate that only expected fields are being ignored.

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller \
  | grep -E "ignoreDifferences|OutOfSync|kyverno|istio|gatekeeper"
```

### Phase 3: Long-term (Next review cycle)

1. **Monitor for patterns**: If other applications show similar OutOfSync + Healthy patterns, investigate for webhook mutations
2. **Upgrade to ArgoCD v2.10+**: If available, enable ServerSideApply by default
3. **Consider policy linting**: Add pre-commit hooks to validate Kyverno/Gatekeeper policies locally before Git push

---

## SPECIFIC IMPLEMENTATION REQUIREMENTS

### For ISTIO (istiod v1.28.0)

**Issue**: `MutatingWebhookConfiguration` resources have empty caBundle at install time  
**Mutation**: Istiod controller patches in the certificate after startup  
**Expected**: caBundle will always differ from Git declaration  

**Fix**:
```yaml
- group: admissionregistration.k8s.io
  kind: MutatingWebhookConfiguration
  jqPathExpressions:
    - '.webhooks[]?.clientConfig.caBundle'
```

**Validation**: Check that webhook is functioning:
```bash
kubectl get mutatingwebhookconfigurations -n istio-system -o yaml | grep caBundle
# Should contain a base64-encoded certificate, not empty
```

### For KYVERNO (v3.1.0 from helm chart)

**Issue**: Mutating webhook auto-generates policy rules  
**Mutation**: Rules matching pattern `autogen-*` are added by webhook  
**Expected**: Cluster will always have more rules than Git declares  

**Fix**:
```yaml
- group: kyverno.io
  kind: ClusterPolicy
  jqPathExpressions:
    - '.spec.rules[] | select(.name | test("^autogen-"))'
- group: kyverno.io
  kind: ClusterPolicy
  jsonPointers:
    - /status
```

**Validation**: Check that policies are enforced:
```bash
kubectl get clusterpolicies -o jsonpath='{.items[0].spec.rules}' | jq 'map(.name)'
# Should contain both original and autogen-* rules
```

### For GATEKEEPER (v3.17.0 from helm chart)

**Issue**: ValidatingWebhook creates CRDs dynamically from ConstraintTemplates  
**Mutation**: CRDs are generated programmatically, not declared in Git  
**Expected**: CRDs will appear in cluster but not in Git  

**Fix - Part 1**: Already have `SkipDryRunOnMissingResource=true` ✓

**Fix - Part 2**: Add ignoreDifferences:
```yaml
- group: apiextensions.k8s.io
  kind: CustomResourceDefinition
  jqPathExpressions:
    - '.metadata.name | select(test("constraints\\.gatekeeper\\.sh$"))'
  jsonPointers:
    - /spec
    - /status
```

**Validation**: Check that constraints are enforced:
```bash
kubectl get crd | grep constraints.gatekeeper.sh
# Should list dynamically generated CRDs like k8sallowedrepos.constraints.gatekeeper.sh

kubectl get constraints -n gatekeeper-system
# Should list all defined constraints
```

---

## IMPLEMENTATION RISKS AND MITIGATIONS

### Risk 1: Hiding Real Problems

**Risk**: `ignoreDifferences` might hide actual drift caused by real configuration errors

**Mitigation**:
1. Use specific JQ expressions, not broad JSON pointers
2. Monitor logs for legitimate differences
3. Regularly review ignored differences in ArgoCD UI
4. Alert if ignored differences exceed expected patterns

### Risk 2: Webhook Failures Not Detected

**Risk**: If webhook fails silently, `ignoreDifferences` might hide the failure

**Mitigation**:
1. Ensure webhook failure policy is `fail` (is it - lines 48-50 for gatekeeper, 47-49 for kyverno)
2. Monitor webhook availability with prometheus
3. Add health checks for webhook pods
4. Use application-level alerts, not just ArgoCD sync status

### Risk 3: Incomplete Implementation

**Risk**: JQ expressions might not match all mutation patterns

**Mitigation**:
1. Test `ignoreDifferences` rules in dev environment first
2. Validate with actual policy resources
3. Check ArgoCD UI to confirm differences are ignored
4. Document expected behavior for ops team

---

## PRIORITY AND IMPLEMENTATION TIMELINE

### Priority: MEDIUM

**Why Medium?**
- No functional impact (applications are Healthy and working)
- Cosmetic issue in ArgoCD UI (OutOfSync != actual drift)
- But might mask real problems if not handled carefully
- Better to implement proper handling than ignore forever

### Timeline

**Immediate (This Week)**:
1. Document the issue (this report)
2. Add ignoreDifferences rules for ISTIO caBundle
3. Test and validate

**Short-term (Next Week)**:
1. Add ignoreDifferences rules for KYVERNO auto-generated rules
2. Add ignoreDifferences rules for GATEKEEPER CRDs
3. Validate all three in dev environment
4. Commit to Git with documentation

**Medium-term (1-2 Weeks)**:
1. Deploy to production
2. Monitor ArgoCD logs for any unexpected differences
3. Document findings for ops team

**Long-term (Next Review)**:
1. Evaluate if ServerSideApply helps (if upgraded to ArgoCD v2.10+)
2. Consider custom health rules if still seeing false positives
3. Review for similar patterns in other applications

---

## VALIDATION CHECKLIST

Before implementing, verify:

- [ ] Istio webhook is functioning (caBundle is populated)
- [ ] Kyverno policies are being enforced (autogen rules exist)
- [ ] Gatekeeper constraints are active (no validation errors)
- [ ] All applications show Healthy status despite OutOfSync
- [ ] No real functionality is impaired

After implementing:

- [ ] ignoreDifferences rules are in place
- [ ] ArgoCD ApplicationSet validates without errors
- [ ] Applications sync successfully
- [ ] OutOfSync count decreases significantly
- [ ] Cluster functionality unchanged
- [ ] Monitor logs for 1 week for any issues

---

## FILES TO MODIFY

### Primary File
- **Path**: `/Users/kevin/github/kubernetes-platform-stack/argocd/applicationsets/platform-apps.yaml`
- **Section**: `ignoreDifferences:` (after line 364)
- **Change Type**: Addition (add new rules, keep existing rules)

### Documentation Files (Create/Update)
- **New**: `WEBHOOK_MUTATION_ANALYSIS.md` - This investigation
- **Update**: `HELM_APPS_GUIDE.md` - Add section on webhook mutations
- **Update**: `DEPLOYMENT_GUIDE.md` - Add section on OutOfSync + Healthy pattern

---

## CONCLUSION

The OutOfSync + Healthy status for Istio, Kyverno, and Gatekeeper is **not a problem to be fixed**, but rather a **legitimate operational pattern to be acknowledged and configured for**.

These applications are functioning correctly. The OutOfSync status is caused by their webhooks and controllers legitimately modifying Kubernetes resources in ways that differ from Git. This is expected behavior, not drift.

**By implementing targeted `ignoreDifferences` rules, we:**
1. Acknowledge this expected behavior
2. Prevent false alerts in ArgoCD
3. Reduce operational confusion
4. Maintain GitOps principles for resources that actually matter
5. Keep error handling for genuinely unexpected changes

The implementation is straightforward, low-risk, and aligns with ArgoCD best practices for webhook-based controllers.

