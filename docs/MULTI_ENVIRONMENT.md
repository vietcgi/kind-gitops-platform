# Multi-Environment Setup (Dev/Staging/Prod)

## Overview

This guide implements Dev, Staging, and Production environments with separate clusters, configurations, and deployment pipelines using GitOps.

---

## Architecture

Each environment has:
- Separate KIND/Kubernetes cluster
- Separate git branch or directory
- Environment-specific configs (resources, replicas, domains)
- Promotion workflow: Dev -> Staging -> Prod

Directory structure:
```
kubernetes-platform-stack/
├── environments/
│   ├── dev/              # Development environment
│   │   ├── argocd/
│   │   │   ├── applications/
│   │   │   └── applicationsets/
│   │   ├── helm/
│   │   │   └── values.yaml  (dev-specific)
│   │   └── kustomization.yaml
│   ├── staging/          # Staging environment
│   │   ├── argocd/
│   │   ├── helm/
│   │   └── kustomization.yaml
│   └── prod/             # Production environment
│       ├── argocd/
│       ├── helm/
│       └── kustomization.yaml
├── shared/               # Shared across all environments
│   ├── base/             # Base configurations
│   ├── crds/             # Custom resources
│   └── manifests/        # Common policies/configs
└── helmfile.yaml         # Helm deployment spec
```

---

## Environment Specifications

### Dev Environment

Purpose: Developer testing, daily builds, rapid iteration

Specs:
- 1-node KIND cluster (minimal resources)
- 1 replica for all services
- Short log retention (7 days)
- No backup policy
- No HA requirements
- Image: latest tags allowed
- Domain: `*.dev.local`

Resource Usage:
- CPU: 2 cores
- Memory: 4 GB
- Storage: 20 GB

Deploy Time: < 5 minutes

```bash
# Deploy dev
./deploy.sh dev

# Or manual
kind create cluster --name platform-dev --config kind-config-dev.yaml
helm install platform -f environments/dev/helmfile.yaml
```

### Staging Environment

Purpose: Pre-production testing, integration tests, performance validation

Specs:
- 2-node KIND cluster
- 2 replicas for critical services
- 30-day log retention
- Weekly backup
- Basic HA (no multi-zone)
- Image: versioned tags only
- Domain: `*.staging.local`

Resource Usage:
- CPU: 4 cores
- Memory: 8 GB
- Storage: 50 GB

Deploy Time: < 15 minutes

```bash
# Deploy staging
./deploy.sh staging

# Verify readiness for prod
./tests/staging-readiness.sh
```

### Production Environment

Purpose: Customer-facing, high availability, full monitoring

Specs:
- 3-node high-availability cluster
- 3 replicas for all critical services
- 90-day log retention (compliance)
- Daily backup with off-site replication
- Multi-zone/multi-node high availability
- Image: signed/scanned images only
- Domain: `*.example.com`

Resource Usage:
- CPU: 12+ cores
- Memory: 32+ GB
- Storage: 500+ GB

Deploy Time: < 30 minutes

```bash
# Deploy prod (requires approval)
./deploy.sh prod

# Pre-deployment checks
./tests/prod-readiness.sh

# Post-deployment validation
./tests/prod-smoke-tests.sh
```

---

## Configuration Management

### Environment-Specific Values

Helm values override by environment:

```bash
# Directory structure
helm/my-app/
├── values.yaml           # Base values
├── values-dev.yaml       # Dev overrides
├── values-staging.yaml   # Staging overrides
└── values-prod.yaml      # Prod overrides
```

Example values-prod.yaml:
```yaml
# Production overrides
replicaCount: 3  # vs 1 in dev
resources:
  limits:
    memory: 1Gi   # Higher than dev
    cpu: 1000m
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
image:
  tag: v1.2.3    # Specific version, not latest
imagePullPolicy: IfNotPresent  # Stricter than dev
```

Deploy with environment values:
```bash
# Dev
helm upgrade my-app helm/my-app \
  -f helm/my-app/values.yaml \
  -f helm/my-app/values-dev.yaml

# Staging
helm upgrade my-app helm/my-app \
  -f helm/my-app/values.yaml \
  -f helm/my-app/values-staging.yaml

# Prod
helm upgrade my-app helm/my-app \
  -f helm/my-app/values.yaml \
  -f helm/my-app/values-prod.yaml
```

### Application Version Pinning

Production uses exact versions:

```yaml
# argocd/applicationsets/platform-apps.yaml

# For each app, define per-environment version:
applications:
  prometheus:
    dev:
      version: "70.10.0"      # Bleeding edge for testing
    staging:
      version: "70.10.0"      # Same as latest dev passed tests
    prod:
      version: "70.9.0"       # Last stable version
```

---

## Git Workflow

### Branch Strategy

```
main branch (prod-ready)
├── release branches (hotfixes)
└── feature branches (new features)

staging branch (test before prod)
├── merges from feature branches
└── merges to main when approved

dev branch (daily builds)
├── all experimental work
└── merges to staging when ready
```

### Promotion Workflow

1. Developer: Create feature branch from dev
2. Developer: Test in dev cluster
3. Dev Team: Approve and merge to dev
4. Staging: Auto-deploy from dev (daily)
5. QA/Staging: Validate in staging cluster
6. Staging Team: Approve merge to main
7. Production: Deploy from main (weekly)
8. Prod Team: Post-deploy validation

Example:
```bash
# Feature development
git checkout -b feature/new-feature dev
git push origin feature/new-feature
# -> PR to dev branch

# Dev testing
./deploy.sh dev

# After dev approval, merge and deploy staging
git checkout staging
git merge dev
git push

# Staging testing
./deploy.sh staging
./tests/prod-readiness.sh

# After staging approval, merge to prod branch
git checkout main
git merge staging
git push

# Prod deployment (with approval gates)
./deploy.sh prod
./tests/prod-smoke-tests.sh
```

---

## ArgoCD Multi-Environment

Create separate ArgoCD instances or use same with selectors:

### Option 1: Separate ArgoCD per Environment

```bash
# Dev ArgoCD
kubectl --context=platform-dev -n argocd get applications

# Staging ArgoCD
kubectl --context=platform-staging -n argocd get applications

# Prod ArgoCD
kubectl --context=platform-prod -n argocd get applications
```

ApplicationSet targets specific cluster:

```yaml
generators:
- matrix:
    generators:
    - list:
        elements:
        - environment: dev
          cluster: https://kubernetes.default.svc  # dev cluster
        - environment: staging
          cluster: https://staging-cluster:6443
        - environment: prod
          cluster: https://prod-cluster:6443
template:
  spec:
    destination:
      server: "{{ .cluster }}"
```

### Option 2: Single ArgoCD with App-of-Apps

Single ArgoCD server manages all environments:

```yaml
# argocd/applications/app-of-apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
spec:
  source:
    path: environments
    # Will deploy dev/, staging/, prod/ apps
```

---

## Testing Strategy

### Dev Testing
```bash
# Unit tests
pytest tests/unit/

# Quick integration test
./tests/dev-integration.sh

# Deploy and manual validation
./deploy.sh dev
kubectl port-forward svc/my-app 8080:8080
curl http://localhost:8080/health
```

### Staging Testing
```bash
# Full integration tests
./tests/staging-integration.sh

# Performance tests
./tests/load-test.sh

# Security scanning
./tests/security-scan.sh

# Production readiness checks
./tests/prod-readiness.sh

# Deployment validation
./tests/deployment-validation.sh
```

### Production Validation
```bash
# Pre-deployment checks
./tests/prod-readiness.sh

# Smoke tests (post-deploy)
./tests/prod-smoke-tests.sh

# Health checks
./tests/prod-health-check.sh

# Production monitoring validation
./tests/prod-monitoring.sh
```

---

## Deployment Gates

### Dev Deployment (Auto)
- Merge to dev branch
- CI passes
- Auto-deploy to dev cluster

### Staging Deployment (Manual Approval)
```bash
# After dev testing passes
git checkout staging
git merge dev  # Requires approval
git push      # Triggers deployment

# Manual deployment if needed
./deploy.sh staging
```

### Production Deployment (Strict Controls)
```bash
# After staging testing passes
git checkout main
git merge staging  # Requires 2+ approvals
git push           # Triggers deployment

# Must complete:
# 1. All tests passing
# 2. Staging validation complete
# 3. Stakeholder approval
# 4. Backup verified
# 5. Runbooks updated
```

---

## Rollback Procedures

### Dev Rollback
Simple - redeploy previous version:
```bash
git revert <bad-commit>
git push
# Auto-redeploys
```

### Staging Rollback
Preserve for investigation:
```bash
# Revert deployment
kubectl rollout undo deployment/<name> -n <namespace>

# Or redeploy from git
git revert <bad-commit>
git push
```

### Production Rollback
Careful, documented process:
```bash
# 1. Assess impact
# 2. Notify stakeholders
# 3. Create incident ticket
# 4. Execute rollback
kubectl rollout undo deployment/<name> -n <namespace>

# Or redeploy previous stable version
git revert <bad-commit>
git push
./deploy.sh prod

# 5. Post-incident review
# Document what happened
# Implement fixes to prevent recurrence
```

---

## Environment Parity

Ensure environments stay synchronized:

```bash
# Weekly parity check
./tests/environment-parity.sh

# Checks:
# - Same Kubernetes versions (allowable drift: 1 minor)
# - Same component versions (exact match for prod)
# - Same network policies
# - Same RBAC policies
# - Same monitoring/logging config
```

---

## Secrets Per Environment

Different credentials for each environment:

```bash
# Dev secrets (shared, not sensitive)
kubectl create secret generic db-creds \
  --from-literal=user=dev \
  --from-literal=pass=dev-password \
  -n default -o yaml | kubeseal -f - > dev-secrets.yaml

# Staging secrets (real but test data)
kubectl create secret generic db-creds \
  --from-literal=user=staging \
  --from-literal=pass=<staging-password> \
  -n default -o yaml | kubeseal -f - > staging-secrets.yaml

# Prod secrets (real, highly secure)
# Created manually, never in git
kubectl create secret generic db-creds \
  --from-literal=user=prod-user \
  --from-literal=pass=<prod-password-from-vault> \
  -n default
```

Reference in ApplicationSet:
```yaml
# argocd/applicationsets/platform-apps.yaml
template:
  spec:
    source:
      helm:
        valueFiles:
        - values.yaml
        - "values-{{ .environment }}.yaml"
        - "secrets-{{ .environment }}.yaml"
```

---

## Monitoring Per Environment

Environment-specific dashboards in Grafana:

```
Grafana Dashboards:
├── Dev Overview
│   ├── Pod health (dev cluster)
│   ├── Error rate (lenient alerts)
│   └── Deployment frequency
├── Staging Overview
│   ├── Pod health (staging cluster)
│   ├── Performance metrics
│   └── Integration test results
└── Prod Overview
    ├── Pod health (prod cluster)
    ├── SLO/SLI tracking
    ├── Alerts and incidents
    └── Business metrics
```

Setup:
```yaml
# manifests/monitoring/grafana-dashboards.yaml
- datasource: Prometheus-Dev
- datasource: Prometheus-Staging
- datasource: Prometheus-Prod
```

---

## Cost Management

Track costs per environment:

```
Monthly Costs (Example):
Dev:       $50    (shared resources)
Staging:   $200   (test scale)
Prod:      $800   (HA setup)
Total:     $1,050

Cost optimization:
- Dev: Shared cluster, low resources
- Staging: Scheduled startup (8 AM - 6 PM only)
- Prod: Reserved instances for predictable load
```

---

## Documentation

Update documentation per environment:

```
docs/
├── ARCHITECTURE.md          # Shared
├── OPERATIONS.md            # Shared
├── CONFIGURATION.md         # Shared
├── MULTI_ENVIRONMENT.md     # This file
├── ENV_DEV.md              # Dev-specific
├── ENV_STAGING.md          # Staging-specific
└── ENV_PROD.md             # Prod-specific
```

Each environment doc covers:
- Setup and prerequisites
- Deployment procedures
- Monitoring and alerts
- Troubleshooting
- Escalation contacts

---

## Checklist: Setting Up Multi-Environment

```
- [ ] Create git branches (dev, staging, main)
- [ ] Create KIND clusters for each environment
- [ ] Update ApplicationSet for per-environment versions
- [ ] Create Helm values overrides for each environment
- [ ] Setup Velero for staging and prod backups
- [ ] Configure Prometheus for each environment
- [ ] Update runbooks with environment-specific procedures
- [ ] Train team on promotion workflow
- [ ] Document environment specifications
- [ ] Test promotion workflow end-to-end
- [ ] Setup cost tracking per environment
- [ ] Create escalation contacts per environment
```

