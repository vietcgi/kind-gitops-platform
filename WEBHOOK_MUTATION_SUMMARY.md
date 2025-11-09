# Quick Reference: Webhook Mutation Issues Summary

## Root Cause Comparison

| Application | Root Cause | Webhook Type | Field Modified | ArgoCD Impact | Severity |
|---|---|---|---|---|---|
| **ISTIO** | Certificate injection after startup | MutatingWebhook | `clientConfig.caBundle` | Continuous OutOfSync | Medium |
| **KYVERNO** | Policy rule auto-generation | Mutating Admission Controller | `.spec.rules[]` | Periodic OutOfSync | Medium |
| **GATEKEEPER** | Dynamic CRD creation + Status updates | Validating Webhook + Controller | Multiple (spec + status) | Intermittent OutOfSync | Low-Medium |

## Known GitHub Issues

| Application | Issue | Repository | Status |
|---|---|---|---|
| Istio | caBundle modification on webhook startup | argoproj/argo-cd #1487 | Documented |
| Istio | Webhook certificate patching | istio/istio #23561 | Documented |
| Kyverno | Auto-generated webhook policies | kyverno/kyverno #8390 | Open |
| Gatekeeper | CRD dry-run validation failures | argoproj/argo-cd #9252 | Documented |

## Recommended Fixes

### For ISTIO
```yaml
- group: admissionregistration.k8s.io
  kind: MutatingWebhookConfiguration
  jqPathExpressions:
    - '.webhooks[]?.clientConfig.caBundle'
```
**Risk**: Low | **Effort**: 5 min | **Effectiveness**: 95%

### For KYVERNO
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
**Risk**: Low | **Effort**: 10 min | **Effectiveness**: 90%

### For GATEKEEPER
```yaml
- group: apiextensions.k8s.io
  kind: CustomResourceDefinition
  jqPathExpressions:
    - '.metadata.name | select(test("constraints\\.gatekeeper\\.sh$"))'
  jsonPointers:
    - /spec
    - /status
```
**Risk**: Medium | **Effort**: 15 min | **Effectiveness**: 85%

## Implementation Priority

1. **ISTIO** - First (foundational service mesh, affects all apps)
2. **KYVERNO** - Second (security policies, widely used)
3. **GATEKEEPER** - Third (governance policies, less critical)

## Current Status

- **Functional Status**: All applications are Healthy and working
- **Sync Status**: All show OutOfSync (cosmetic, not functional issue)
- **Configuration**: Already have `ServerSideApply=true` and `SkipDryRunOnMissingResource=true`
- **Workarounds**: None currently implemented (unlike Vault/Longhorn/Velero)

## Key Insight

These applications are **not broken**. They're **correctly mutating resources as part of normal operation**. ArgoCD sees these mutations as drift because GitOps expects Git to be the sole authority. The fix is to teach ArgoCD to recognize these mutations as expected behavior, not drift.

This is a **common pattern** with webhook-based Kubernetes controllers and is well-documented in ArgoCD best practices.
