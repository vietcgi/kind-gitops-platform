# Platform Improvement Plan: A- to A+

## Current Assessment
**Grade**: A- (Production-ready with minor improvements)
**Target**: A+ (Production-hardened enterprise platform)

---

## HIGH PRIORITY (Complete First)

### 1. Fix Helm Resource Adoption for CoreDNS and Cilium
**Issue**: ArgoCD shows "OutOfSync" for CoreDNS/Cilium because deploy.sh creates Helm releases that ArgoCD can't properly adopt.

**Impact**: Confusing UX, operators don't know if drift is real or expected.

**Solution**:
- Add `RespectIgnoreDifferences=true` to syncOptions
- Configure ArgoCD to adopt existing Helm releases
- Add proper annotations for ownership transfer

**Files to modify**:
- `argocd/applicationsets/platform-apps.yaml`

**Implementation**:
```yaml
# For CoreDNS and Cilium entries, add:
syncPolicy:
  syncOptions:
    - RespectIgnoreDifferences=true
    - ServerSideApply=true
  automated:
    prune: false  # Never prune bootstrap resources
    selfHeal: true
```

**Acceptance criteria**:
- [ ] `kubectl get application coredns -n argocd` shows "Synced"
- [ ] `kubectl get application cilium -n argocd` shows "Synced"
- [ ] No drift warnings for bootstrap-installed resources

---

### 2. Add Granular Sync Waves
**Issue**: Only 2 sync wave levels (-1 and 0) causes dependency issues during bootstrap.

**Impact**: Slower convergence, potential race conditions, harder troubleshooting.

**Solution**: Implement 8-level sync wave hierarchy.

**Files to modify**:
- `argocd/applicationsets/platform-apps.yaml`

**New sync wave mapping**:
```yaml
syncWave: -10  # CRD-only apps
  - prometheus-crds
  - cert-manager (CRDs only)

syncWave: -5   # Network foundation
  - cilium
  - coredns

syncWave: -3   # Security foundation
  - gatekeeper
  - kyverno
  - falco

syncWave: -1   # Secrets and certificates
  - cert-manager
  - sealed-secrets
  - vault
  - vault-certificate

syncWave: 0    # Ingress and routing
  - kong
  - istio
  - external-dns

syncWave: 5    # Observability
  - prometheus
  - loki
  - tempo
  - jaeger
  - grafana
  - blackbox-exporter
  - metrics-server

syncWave: 10   # Storage
  - longhorn
  - velero

syncWave: 15   # Everything else
  - harbor
  - kyverno-policies
  - platform-monitoring
  - platform-network-policies-bootstrap
  - kong-ingress-routes
```

**Acceptance criteria**:
- [ ] Applications deploy in correct dependency order
- [ ] No "dependency not ready" errors during bootstrap
- [ ] Bootstrap time improves or stays same
- [ ] Documentation updated with sync wave rationale

---

### 3. Add Application Tier Labels
**Issue**: Health checks in deploy.sh are hardcoded, not dynamic.

**Impact**: Adding new critical apps requires code changes, not configuration.

**Solution**: Label applications by tier and make health checks label-based.

**Files to modify**:
- `argocd/applicationsets/platform-apps.yaml`
- `deploy.sh`
- `scripts/health-check.sh`

**Add to ApplicationSet template**:
```yaml
metadata:
  labels:
    tier: '{{ .tier }}'  # infrastructure, security, observability, storage, other
    criticality: '{{ .criticality }}'  # critical, high, medium, low
```

**Add tier field to each app**:
```yaml
- name: cilium
  tier: infrastructure
  criticality: critical

- name: prometheus
  tier: observability
  criticality: high
```

**Update deploy.sh health checks**:
```bash
# Replace hardcoded checks with:
CRITICAL_APPS=$(kubectl get applications -n argocd -l criticality=critical -o jsonpath='{.items[*].metadata.name}')
for app in $CRITICAL_APPS; do
  check_argocd_app_sync "$app"
  check_argocd_app_health "$app"
done
```

**Acceptance criteria**:
- [ ] All applications have tier and criticality labels
- [ ] deploy.sh dynamically checks critical apps
- [ ] Adding new critical app requires no code changes

---

## MEDIUM PRIORITY (Complete Second)

### 4. Add Default Network Policies
**Issue**: Namespaces may not have default-deny policies, risking accidental exposure.

**Impact**: Security gap - pods can communicate unexpectedly.

**Solution**: Create namespace-scoped default deny policies.

**Files to create**:
- `helm/platform-network-policies/templates/default-deny.yaml`

**Implementation**:
```yaml
# For each application namespace, create:
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: {{ .namespace }}
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress

# Then add specific allow rules per app
```

**Acceptance criteria**:
- [ ] Every namespace has default-deny NetworkPolicy
- [ ] Explicit allow rules for required communication
- [ ] No application breakage after deployment
- [ ] Document network policy architecture

---

### 5. Create Admission Controller Baseline Policies
**Issue**: Gatekeeper and Kyverno installed but no default policies.

**Impact**: No enforcement of security best practices.

**Solution**: Add baseline policies for common violations.

**Files to create**:
- `helm/kyverno-policies/templates/require-resource-limits.yaml`
- `helm/kyverno-policies/templates/disallow-host-path.yaml`
- `helm/kyverno-policies/templates/disallow-privileged.yaml`
- `helm/kyverno-policies/templates/require-non-root.yaml`

**Policy list**:
```yaml
# Kyverno ClusterPolicies:
1. require-resource-limits (warn mode initially)
2. disallow-host-path (enforce mode)
3. disallow-privileged (enforce mode)
4. require-non-root-user (warn mode initially)
5. restrict-image-registries (enforce for production namespaces)
6. require-pod-probes (warn mode)
```

**Acceptance criteria**:
- [ ] Baseline policies deployed to cluster
- [ ] Policy violations visible in Kyverno reports
- [ ] No breakage of existing workloads (use warn mode first)
- [ ] Document policy enforcement strategy

---

### 6. Add Grafana Dashboards as Code
**Issue**: Observability stack deployed but no default dashboards.

**Impact**: Operators must manually import dashboards.

**Solution**: Manage Grafana dashboards as ConfigMaps via ArgoCD.

**Files to create**:
- `helm/grafana/dashboards/kubernetes-cluster.json`
- `helm/grafana/dashboards/argocd.json`
- `helm/grafana/dashboards/cilium.json`
- `helm/grafana/templates/dashboard-configmaps.yaml`

**Dashboard sources**:
- Kubernetes cluster monitoring: https://grafana.com/grafana/dashboards/7249
- ArgoCD: https://grafana.com/grafana/dashboards/14584
- Cilium: https://grafana.com/grafana/dashboards/16611
- Prometheus: https://grafana.com/grafana/dashboards/3662

**Acceptance criteria**:
- [ ] Dashboards automatically imported on Grafana startup
- [ ] Dashboards versioned in Git
- [ ] Documentation for adding custom dashboards

---

### 7. Add Prometheus Alert Rules
**Issue**: Prometheus deployed but no alerting configured.

**Impact**: No automated notifications for platform issues.

**Solution**: Deploy PrometheusRule CRDs with baseline alerts.

**Files to create**:
- `helm/platform-monitoring/templates/alerts-infrastructure.yaml`
- `helm/platform-monitoring/templates/alerts-applications.yaml`

**Critical alerts**:
```yaml
# Infrastructure alerts:
- NodeNotReady (critical)
- NodeMemoryPressure (warning)
- NodeDiskPressure (warning)
- PodCrashLooping (critical)
- PersistentVolumeClaimPending (warning)

# Application alerts:
- ArgoCDAppOutOfSync (warning)
- ArgoCDAppUnhealthy (critical)
- CertificateExpiringSoon (warning)
- VaultSealed (critical)
```

**Acceptance criteria**:
- [ ] Alert rules deployed and active in Prometheus
- [ ] Alerts visible in Prometheus UI
- [ ] Test alerts fire correctly
- [ ] Document alert runbooks

---

## LOW PRIORITY (Nice to Have)

### 8. Add Pre-commit Hooks for Validation
**Issue**: No automated validation before commit.

**Impact**: YAML errors only discovered after push.

**Solution**: Add pre-commit hooks for YAML/JSON validation.

**Files to create**:
- `.pre-commit-config.yaml`
- `.github/workflows/validate.yaml` (if using GitHub)

**Validations**:
```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    hooks:
      - id: check-yaml
      - id: check-json
      - id: end-of-file-fixer

  - repo: https://github.com/adrienverge/yamllint
    hooks:
      - id: yamllint

  # Custom: Validate ApplicationSet generates successfully
  - repo: local
    hooks:
      - id: validate-applicationset
        name: Validate ApplicationSet
        entry: kubectl apply --dry-run=client -f argocd/applicationsets/
        language: system
```

**Acceptance criteria**:
- [ ] Pre-commit hooks installed
- [ ] YAML/JSON validated before commit
- [ ] CI/CD validates on pull request
- [ ] Documentation for contributors

---

### 9. Document Upgrade Procedures
**Issue**: No documented process for upgrading Helm charts.

**Impact**: Risky upgrades, potential downtime.

**Solution**: Create upgrade runbooks for each major component.

**Files to create**:
- `docs/upgrades/README.md`
- `docs/upgrades/cilium.md`
- `docs/upgrades/argocd.md`
- `docs/upgrades/prometheus.md`

**Runbook template**:
```markdown
# Upgrading [Component]

## Pre-upgrade checklist
- [ ] Review changelog
- [ ] Check breaking changes
- [ ] Backup current state
- [ ] Test in non-prod environment

## Upgrade procedure
1. Update version in platform-apps.yaml
2. Update values.yaml if needed
3. Commit and push changes
4. Monitor ArgoCD sync
5. Validate deployment

## Rollback procedure
1. Revert Git commit
2. Force sync application
3. Validate rollback

## Post-upgrade validation
- [ ] Check application health
- [ ] Verify functionality
- [ ] Review logs for errors
```

**Acceptance criteria**:
- [ ] Runbooks for critical components
- [ ] Tested upgrade procedures
- [ ] Rollback procedures documented

---

### 10. Split ApplicationSet if Scale Increases
**Issue**: Single 600-line file becomes harder to review at 40+ apps.

**Impact**: Lower risk currently, prepare for growth.

**Solution**: Split by domain when approaching 40 applications.

**Target structure**:
```
argocd/applicationsets/
  platform-infrastructure.yaml   (CNI, DNS, ingress, storage)
  platform-security.yaml          (Vault, policies, admission)
  platform-observability.yaml     (Prometheus, Loki, Grafana)
  platform-other.yaml             (Harbor, misc tools)
```

**Acceptance criteria**:
- [ ] Only execute if application count > 40
- [ ] Maintain consistent templating
- [ ] No functional changes
- [ ] Update root-app to reference all ApplicationSets

---

## Success Metrics

### Platform Reliability
- [ ] Zero unexpected OutOfSync applications
- [ ] Bootstrap completes in < 15 minutes
- [ ] All critical apps achieve Healthy status within 20 minutes
- [ ] Zero policy violations in production namespaces

### Operational Excellence
- [ ] All platform changes reviewed via Git
- [ ] Alerts fire for all critical conditions
- [ ] Dashboards cover all critical metrics
- [ ] Runbooks exist for all operational procedures

### Developer Experience
- [ ] Clear documentation for adding new applications
- [ ] Automated validation catches errors before deploy
- [ ] Observability tools easily accessible
- [ ] Network policies don't block legitimate traffic

---

## Implementation Timeline

### Week 1: High Priority (Critical Path)
- Day 1-2: Fix Helm resource adoption (#1)
- Day 3-4: Add granular sync waves (#2)
- Day 5: Add application tier labels (#3)
- **Milestone**: Platform shows clean sync state, proper dependency ordering

### Week 2: Medium Priority (Security & Observability)
- Day 1-2: Add default network policies (#4)
- Day 3-4: Create admission controller policies (#5)
- Day 5: Add Grafana dashboards and Prometheus alerts (#6, #7)
- **Milestone**: Security baseline enforced, observability complete

### Week 3: Low Priority (Process & Documentation)
- Day 1-2: Add pre-commit hooks (#8)
- Day 3-5: Document upgrade procedures (#9)
- **Milestone**: Operational maturity achieved

### Week 4: Buffer & Testing
- Day 1-3: End-to-end testing
- Day 4: Fix issues discovered in testing
- Day 5: Final validation and documentation
- **Milestone**: A+ grade achieved

---

## Grade Advancement Criteria

**Current: A-**
- ✅ Hybrid bootstrap pattern working
- ✅ GitOps with ArgoCD functioning
- ✅ Official Helm charts used
- ⚠️ Resource drift on bootstrap apps
- ⚠️ Limited sync wave granularity
- ⚠️ Hardcoded health checks

**After High Priority: A**
- ✅ Clean sync state (no drift warnings)
- ✅ Granular dependency ordering
- ✅ Dynamic health monitoring
- ✅ Production-ready baseline

**After Medium Priority: A+**
- ✅ Security baseline enforced
- ✅ Default deny network policies
- ✅ Complete observability with dashboards and alerts
- ✅ Operational excellence achieved

**After Low Priority: A+ (Hardened)**
- ✅ Automated validation pipeline
- ✅ Comprehensive documentation
- ✅ Repeatable upgrade procedures
- ✅ Enterprise-grade platform

---

## Notes

### Why Not Change Bootstrap Pattern?
The hybrid Helm + ArgoCD pattern is correct and used by industry leaders:
- Google Anthos
- AWS EKS Blueprints
- Azure AKS with Flux/ArgoCD

**Don't change**: Core architecture is sound.

### Why Keep Large ApplicationSet?
Single ApplicationSet pattern is:
- Easier to maintain than 20+ individual files
- Standard practice for 20-30 applications
- Used by major cloud providers

**Don't split** until you exceed 40 applications.

### What About Secrets Management?
You have Vault deployed - that's good. Consider adding:
- External Secrets Operator (sync from Vault to K8s Secrets)
- Sealed Secrets (encrypt secrets in Git)

This is **future enhancement**, not required for A+ grade.

---

## Questions? Issues?

Open issues in the repository with label `improvement-plan` for tracking.

Track progress with GitHub Projects or similar tool.

**Target completion**: 4 weeks from start date.
**Expected outcome**: Production-hardened A+ platform.
