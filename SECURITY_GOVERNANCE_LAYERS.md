# Security and Governance Layers

## Overview

This document describes the Security and Governance layers added to the Kubernetes Platform Stack. These 7 applications provide enterprise-grade security, compliance, and policy enforcement capabilities.

## Architecture

```
Kubernetes Platform Stack
├── Observability Stack
│   ├── Prometheus (metrics)
│   ├── Loki (logs)
│   └── Tempo (traces)
├── Service Mesh
│   └── Istio
├── Security Layer (NEW)
│   ├── Cert-Manager (TLS certificates)
│   ├── Vault (secrets management)
│   ├── Falco (runtime security)
│   ├── Kyverno (policy engine)
│   └── Sealed-Secrets (encrypted secrets for git)
├── Governance Layer (NEW)
│   ├── Gatekeeper (policy enforcement)
│   └── Audit-Logging (compliance/audit)
└── Application
    └── my-app
```

## Security Layer

### 1. Cert-Manager (v1.14.0)
**Purpose**: Kubernetes-native TLS certificate management

**Key Features**:
- Automatic certificate provisioning and renewal
- Integration with Let's Encrypt and other CAs
- Webhook for automatic certificate injection
- Support for multiple certificate sources

**Helm Chart**: `helm/cert-manager/`
- Namespace: `cert-manager`
- Replicas: 1
- Resources: CPU 100m-500m, Memory 256Mi-1Gi
- RBAC: Enabled
- Security Context: Non-root, read-only filesystem

**ArgoCD Application**: `argocd/applications/cert-manager.yaml`
- Auto-sync enabled
- Creates namespace automatically

### 2. Vault (v1.17.0)
**Purpose**: Secure secrets management and encryption-as-a-service

**Key Features**:
- Multi-authentication methods (Kubernetes, LDAP, OAuth, etc.)
- Secret engines for databases, SSH, PKI, transit encryption
- Audit logging for compliance
- High availability support

**Helm Chart**: `helm/vault/`
- Namespace: `vault`
- Replicas: 1
- Storage: 5Gi (configurable)
- Resources: CPU 100m-500m, Memory 256Mi-1Gi
- RBAC: Enabled
- Security Context: Non-root, read-only filesystem

**ArgoCD Application**: `argocd/applications/vault.yaml`
- Auto-sync enabled
- Creates namespace automatically

### 3. Falco (v0.37.0)
**Purpose**: Runtime security and threat detection

**Key Features**:
- eBPF-based system call tracing
- Real-time threat detection
- Customizable detection rules
- Multiple output backends (Webhook, Kafka, etc.)

**Helm Chart**: `helm/falco/`
- Namespace: `falco`
- DaemonSet: Runs on all nodes
- Resources: CPU 100m-1000m, Memory 256Mi-1Gi
- eBPF enabled for reduced overhead
- RBAC: Enabled
- Security Context: Privileged (required for system monitoring)

**ArgoCD Application**: `argocd/applications/falco.yaml`
- Auto-sync enabled
- Creates namespace automatically

### 4. Kyverno (v1.12.0)
**Purpose**: Kubernetes-native policy engine for validation and mutation

**Key Features**:
- Policy-as-code for Kubernetes resources
- Validation rules (reject non-compliant resources)
- Mutation rules (auto-remediate resources)
- Background scanning for existing resources

**Helm Chart**: `helm/kyverno/`
- Namespace: `kyverno`
- Replicas: 1
- Resources: CPU 100m-500m, Memory 256Mi-1Gi
- ValidatingAdmissionWebhook: Enabled, fail policy
- MutatingAdmissionWebhook: Enabled, fail policy
- Background scan: Enabled
- RBAC: Enabled
- Security Context: Non-root, read-only filesystem

**ArgoCD Application**: `argocd/applications/kyverno.yaml`
- Auto-sync enabled
- Creates namespace automatically

### 5. Sealed-Secrets (v0.25.0)
**Purpose**: Encrypted secrets management for GitOps

**Key Features**:
- Encryption at rest with sealing keys
- Safe to store encrypted secrets in git
- Automatic decryption in-cluster
- Sealing key rotation support
- Prometheus metrics

**Helm Chart**: `helm/sealed-secrets/`
- Namespace: `sealed-secrets`
- Replicas: 1
- Resources: CPU 50m-200m, Memory 64Mi-256Mi
- Sealing key rotation: Disabled (configurable)
- Service Monitor: Enabled
- RBAC: Enabled
- Security Context: Non-root, read-only filesystem

**ArgoCD Application**: `argocd/applications/sealed-secrets.yaml`
- Auto-sync enabled
- Creates namespace automatically

## Governance Layer

### 6. Gatekeeper (v3.17.0)
**Purpose**: Open Policy Agent (OPA) for policy enforcement

**Key Features**:
- Constraint templates for reusable policies
- Constraint instances for specific policy enforcement
- Audit interval for continuous compliance monitoring
- Match kind filtering for granular policy application

**Helm Chart**: `helm/gatekeeper/`
- Namespace: `gatekeeper-system`
- Replicas: 1
- Resources: CPU 100m-500m, Memory 256Mi-1Gi
- ValidatingAdmissionWebhook: Enabled, fail policy
- Audit interval: 60 seconds
- Service Monitor: Enabled
- RBAC: Enabled
- Security Context: Non-root, read-only filesystem

**ArgoCD Application**: `argocd/applications/gatekeeper.yaml`
- Auto-sync enabled
- Creates namespace automatically

### 7. Audit-Logging (v1.0.0)
**Purpose**: Kubernetes API server audit logging for compliance

**Key Features**:
- API audit event logging
- Configurable log levels (Metadata, Request, RequestResponse)
- Log rotation and retention policies
- Webhook backend for log forwarding
- Falco Exporter integration for log analysis

**Helm Chart**: `helm/audit-logging/`
- Namespace: `audit-logging`
- Log level: Metadata
- Max age: 30 days
- Max backup: 10 files
- Max size: 100 MB per file
- Webhook backend: Enabled
- Storage: Configurable (disabled by default)

**ArgoCD Application**: `argocd/applications/audit-logging.yaml`
- Auto-sync enabled
- Creates namespace automatically

## Deployment

All security and governance apps are deployed via ArgoCD in a GitOps-first model:

1. **Direct Helm Installs**: Only Cilium and ArgoCD
2. **ArgoCD-Managed**: All 12 other apps (observability, service mesh, security, governance, application)

### Deploy Steps

```bash
# Only 2 direct Helm installs
helm install cilium cilium/cilium --namespace kube-system --values helm/cilium/values.yaml
helm install argocd argoproj/argo-cd --namespace argocd --values helm/argocd/values.yaml

# Apply all ArgoCD applications (12 total)
kubectl apply -f argocd/applications/

# ArgoCD will automatically sync all applications within 30 seconds
```

### Namespace Organization

Security and Governance apps create their own namespaces:
- `cert-manager`: Cert-Manager
- `vault`: Vault
- `falco`: Falco runtime security
- `kyverno`: Kyverno policy engine
- `sealed-secrets`: Sealed-Secrets
- `gatekeeper-system`: Gatekeeper
- `audit-logging`: Audit-Logging

## Integration Points

### Cert-Manager
- Integrates with Istio for certificate injection
- Creates ClusterIssuer for Let's Encrypt
- Manages certificates across namespaces

### Vault
- Multi-auth methods: Kubernetes service account auth
- Secret engines: Database, SSH, PKI, Transit
- Used by applications for secure secret retrieval

### Falco
- Outputs to multiple backends (stdout, Webhook, Kafka)
- Integrates with observability stack for visualization
- Custom rules file for environment-specific detection

### Kyverno
- Validates pod security standards
- Mutates resources to enforce standards
- Integrates with security context policies

### Sealed-Secrets
- Encrypts all application secrets
- Safe to commit to git with sealing keys in separate secret
- Works with ArgoCD for automatic decryption

### Gatekeeper
- Enforces organizational policies via OPA
- Example policies: image registries, resource quotas, label requirements
- Continuous audit of cluster compliance

### Audit-Logging
- Captures all API server events
- Webhook backend for SIEM integration
- Long-term retention for compliance

## Security Considerations

### Pod Security
- All apps run as non-root users
- Read-only root filesystems (except Falco which needs system access)
- Capability dropping (all except Falco)
- No privilege escalation allowed

### Network Security
- Network policies via Cilium
- mTLS via Istio
- Admission webhook failure policies set to "fail" (deny non-compliant resources)

### Secret Management
- Vault for sensitive secrets
- Sealed-Secrets for git-stored secrets
- No hardcoded credentials

## Configuration

### Custom Values
Each Helm chart has a `values.yaml` file with configurable options:

- Resource requests/limits
- Replica counts
- Node selectors and tolerations
- Service configuration
- Feature flags

Override defaults during ArgoCD sync:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
spec:
  source:
    helm:
      values: |
        cert-manager:
          replicaCount: 3
          resources:
            requests:
              cpu: 200m
```

## Monitoring and Observability

Most apps export Prometheus metrics:

- **Cert-Manager**: Certificate expiration metrics
- **Vault**: Auth and audit metrics
- **Kyverno**: Policy enforcement metrics
- **Sealed-Secrets**: Sealing operations metrics

Service Monitors are included for Prometheus scraping.

## Troubleshooting

### Check Application Status
```bash
kubectl get applications -n argocd
argocd app get cert-manager
```

### View Application Logs
```bash
kubectl logs -n cert-manager -l app=cert-manager
kubectl logs -n vault -l app=vault
kubectl logs -n falco -l app=falco
```

### Sync Issues
```bash
# Force sync an application
argocd app sync cert-manager

# Check diff
argocd app diff cert-manager
```

## Future Enhancements

- Multi-replica deployments for HA
- Custom constraint templates for Gatekeeper
- Vault enterprise features (namespaces, RAFT storage)
- Advanced Falco rule sets
- Custom Kyverno policies per workload

## References

- [Cert-Manager](https://cert-manager.io/)
- [HashiCorp Vault](https://www.vaultproject.io/)
- [Falco](https://falco.org/)
- [Kyverno](https://kyverno.io/)
- [Sealed-Secrets](https://github.com/sealed-secrets/sealed-secrets)
- [Gatekeeper](https://open-policy-agent.github.io/gatekeeper/)
- [Kubernetes Audit](https://kubernetes.io/docs/tasks/debug-application-cluster/audit/)
