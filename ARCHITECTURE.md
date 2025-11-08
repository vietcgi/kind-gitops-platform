# Kubernetes Platform Stack - Architecture

## Overview

This document describes the complete architecture of the Kubernetes Platform Stack, a production-ready Kubernetes platform built with KIND, Cilium, Istio, ArgoCD, and full observability stack.

**Cluster Configuration**: 1 control-plane + 1 worker (Kubernetes v1.33.0)
**Total Deployed Components**: 7 major applications
**Deployment Method**: Helm (all components)
**High Availability**: Ready for multi-node production deployment

---

## System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│              Kubernetes Cluster (v1.33.0, KIND or Cloud)             │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌────────────────────────┐         ┌────────────────────────┐      │
│  │   Control Plane        │         │     Worker Node        │      │
│  │ (No kube-proxy)        │         │ (No kube-proxy)        │      │
│  │                        │         │                        │      │
│  │ - API Server           │◄────────┤ - kubelet              │      │
│  │ - Controller Manager   │         │ - Container Runtime    │      │
│  │ - Scheduler            │         │                        │      │
│  │ - etcd                 │         └────────────────────────┘      │
│  └────────────────────────┘                    │                     │
│         │                                      │                     │
│         └──────────────────┬───────────────────┘                     │
│                            │                                         │
│          ┌─────────────────▼──────────────────┐                      │
│          │   LAYER 1: NETWORKING              │                      │
│          │   Cilium eBPF CNI (v1.17.0)        │                      │
│          │                                    │                      │
│          │  ✓ eBPF-based networking          │                      │
│          │  ✓ kube-proxy replacement         │                      │
│          │  ✓ BGP Control Plane              │                      │
│          │  ✓ Network Policy Engine          │                      │
│          │  ✓ L2/L3 load balancing           │                      │
│          │  ✓ Service mesh integration       │                      │
│          │                                    │                      │
│          └─────────────────┬──────────────────┘                      │
│                            │                                         │
│          ┌─────────────────▼──────────────────┐                      │
│          │   LAYER 2: SERVICE MESH            │                      │
│          │   Istio (v1.28.0)                  │                      │
│          │                                    │                      │
│          │  ┌────────────────────────────┐   │                      │
│          │  │ istiod Control Plane       │   │                      │
│          │  │ - Traffic Management       │   │                      │
│          │  │ - mTLS Enforcement         │   │                      │
│          │  │ - Authorization Policies   │   │                      │
│          │  │ - Certificate Management   │   │                      │
│          │  └────────────────────────────┘   │                      │
│          │                                    │                      │
│          │  ✓ VirtualService routing         │                      │
│          │  ✓ DestinationRule policies       │                      │
│          │  ✓ PeerAuthentication (mTLS)      │                      │
│          │  ✓ AuthorizationPolicy (RBAC)     │                      │
│          │  ✓ Gateway API support            │                      │
│          │  ✓ Sidecar proxy injection        │                      │
│          │                                    │                      │
│          └────────┬──────────────────┬────────┘                      │
│                   │                  │                               │
│      ┌────────────▼──┐        ┌──────▼──────────┐                   │
│      │ LAYER 3: APPS │        │ LAYER 4: OBS    │                   │
│      └────────────┬──┘        └──────┬──────────┘                   │
│                   │                  │                               │
│   ┌───────────────▼────────┐  ┌──────▼──────────────────────┐      │
│   │   my-app (Helm)        │  │  Observability Stack        │      │
│   │   ────────────────     │  │  ──────────────────────     │      │
│   │                        │  │                             │      │
│   │  Namespace: app        │  │  Namespace: monitoring      │      │
│   │                        │  │                             │      │
│   │ Deployment:            │  │ ┌─────────────────────┐    │      │
│   │  - Replicas: 1-3       │  │ │ Prometheus (2.48)   │    │      │
│   │  - Image: custom app   │  │ │ ────────────────    │    │      │
│   │  - Port: 8080/TCP      │  │ │                     │    │      │
│   │                        │  │ │ ✓ Scrape metrics    │    │      │
│   │ Service:               │  │ │ ✓ AlertManager      │    │      │
│   │  - Type: LoadBalancer  │  │ │ ✓ Node Exporter     │    │      │
│   │  - Port: 80→8080       │  │ │ ✓ Kube-state-metrics│    │      │
│   │  - BGP advertise       │  │ └─────────────────────┘    │      │
│   │                        │  │                             │      │
│   │ HPA:                   │  │ ┌─────────────────────┐    │      │
│   │  - Min: 1, Max: 5      │  │ │ Grafana (v11)       │    │      │
│   │  - 80% CPU/Memory      │  │ │ ────────────────    │    │      │
│   │                        │  │ │                     │    │      │
│   │ Istio Configuration:   │  │ │ ✓ Dashboards        │    │      │
│   │  - VirtualService      │  │ │ ✓ Alerting          │    │      │
│   │  - DestinationRule     │  │ │ ✓ Data sources      │    │      │
│   │  - PeerAuth (mTLS)     │  │ │ ✓ Loki integration  │    │      │
│   │  - AuthPolicy          │  │ │ ✓ Tempo integration │    │      │
│   │                        │  │ └─────────────────────┘    │      │
│   │ Cilium Integration:    │  │                             │      │
│   │  - NetworkPolicy       │  │ ┌─────────────────────┐    │      │
│   │  - Default-deny        │  │ │ Loki (v3.0)         │    │      │
│   │  - Explicit allow      │  │ │ ────────────────    │    │      │
│   │                        │  │ │                     │    │      │
│   │ Observability:         │  │ │ ✓ Log aggregation   │    │      │
│   │  - ServiceMonitor      │  │ │ ✓ Promtail shipper  │    │      │
│   │  - Prometheus metrics  │  │ │ ✓ Query interface   │    │      │
│   │  - Health checks       │  │ │ ✓ Retention policy  │    │      │
│   │                        │  │ └─────────────────────┘    │      │
│   │ HA & Resilience:       │  │                             │      │
│   │  - PodDisruptionBudget │  │ ┌─────────────────────┐    │      │
│   │  - Pod anti-affinity   │  │ │ Tempo (v2.3)        │    │      │
│   │  - Resource limits     │  │ │ ────────────────    │    │      │
│   │                        │  │ │                     │    │      │
│   └────────────────────────┘  │ │ ✓ Distributed traces│    │      │
│                                │ │ ✓ Service latency   │    │      │
│                                │ │ ✓ Trace correlation │    │      │
│                                │ │ ✓ Span metrics      │    │      │
│                                │ └─────────────────────┘    │      │
│                                └──────────────────────────────┘      │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │   LAYER 5: ORCHESTRATION & GITOPS                        │       │
│  │   ArgoCD (v3.2.0)                                        │       │
│  │                                                          │       │
│  │   Namespace: argocd                                     │       │
│  │                                                          │       │
│  │  ┌────────────────────────────────────────────────┐    │       │
│  │  │ ArgoCD Server                                  │    │       │
│  │  │ - Web UI (LoadBalancer)                        │    │       │
│  │  │ - API Server                                   │    │       │
│  │  │ - Auth (admin/dex/OIDC)                        │    │       │
│  │  │ - RBAC                                         │    │       │
│  │  └────────────────────────────────────────────────┘    │       │
│  │                                                          │       │
│  │  ┌────────────────────────────────────────────────┐    │       │
│  │  │ Application Controller                         │    │       │
│  │  │ - Monitors git repo                            │    │       │
│  │  │ - Detects drift                                │    │       │
│  │  │ - Auto-syncs (if enabled)                      │    │       │
│  │  │ - Manages Application CRDs                     │    │       │
│  │  └────────────────────────────────────────────────┘    │       │
│  │                                                          │       │
│  │  ┌────────────────────────────────────────────────┐    │       │
│  │  │ Repository Server                              │    │       │
│  │  │ - Clones git repos                             │    │       │
│  │  │ - Generates manifests (Helm)                   │    │       │
│  │  │ - Caches for performance                       │    │       │
│  │  │ - Supports multiple plugins                    │    │       │
│  │  └────────────────────────────────────────────────┘    │       │
│  │                                                          │       │
│  │  ┌────────────────────────────────────────────────┐    │       │
│  │  │ Notifications Controller                       │    │       │
│  │  │ - Webhook events                               │    │       │
│  │  │ - Slack/Email notifications                    │    │       │
│  │  │ - Sync status alerts                           │    │       │
│  │  └────────────────────────────────────────────────┘    │       │
│  │                                                          │       │
│  │  Git Repository Connection:                            │       │
│  │   → URL: https://github.com/vietcgi/...               │       │
│  │   → Branch: main                                       │       │
│  │   → Path: argocd/                                      │       │
│  │   → Sync Interval: 30s                                 │       │
│  │                                                          │       │
│  └──────────────────────────────────────────────────────────┘       │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
         │
         │ (BGP Announcements)
         │ (LoadBalancer IPs)
         │
    ┌────▼────────────────────────────┐
    │  External Network (Optional)     │
    │                                  │
    │  BGP Router/Border Gateway       │
    │  - ASN: 65000+                   │
    │  - Neighbor: Cilium nodes (ASN)  │
    │  - Accepts: LB IPs, Pod CIDRs    │
    │  - Announces to external world   │
    │                                  │
    └────────────────────────────────┘
```

---

## Component Details

### Layer 1: Networking - Cilium (v1.17.0)

**Purpose**: Container networking, kube-proxy replacement, BGP support

**Namespace**: `kube-system`

**Key Features**:
- **eBPF Networking**: Kernel-level packet processing for high performance
- **kube-proxy Replacement**: Native Service load balancing (no iptables)
- **BGP Control Plane**: Advertise LoadBalancer IPs to external routers
- **Network Policies**: Fine-grained pod-to-pod traffic control
- **Host Datapath**: Direct kernel integration for lower latency

**Helm Chart**: `helm/cilium/`
- **Chart Version**: 1.17.0
- **Values File**: `helm/cilium/values.yaml`
- **Templates**:
  - `bgp-cluster-config.yaml` - BGP configuration
  - `network-policies.yaml` - Default deny + explicit allow rules

**Deployed Resources**:
```
Namespace: kube-system
├── DaemonSet: cilium
├── CiliumBGPClusterConfig: cilium-bgp
├── CiliumNetworkPolicy: default-deny-ingress, allow-dns, allow-app-traffic
└── ServiceAccount: cilium
```

**How it Works**:
1. Every node runs a Cilium agent (DaemonSet)
2. Uses eBPF to intercept and process network packets in kernel
3. Maintains connection tracking and service routing tables
4. Announces Service LoadBalancer IPs via BGP to configured routers
5. Enforces network policies at the pod level

**Monitoring**:
```bash
# Check Cilium agents
kubectl get pods -n kube-system -l k8s-app=cilium

# Check BGP status
kubectl get CiliumBGPClusterConfig -n kube-system
kubectl logs -n kube-system -l k8s-app=cilium | grep BGP

# Verify service load balancing
kubectl get svc -A
```

---

### Layer 2: Service Mesh - Istio (v1.28.0)

**Purpose**: Advanced traffic management, security (mTLS), observability

**Namespaces**: `istio-system` (control plane), `app` (data plane)

**Key Features**:
- **mTLS Enforcement**: Automatic encryption between services
- **Traffic Management**: VirtualService for routing, DestinationRule for policies
- **Authorization**: Fine-grained access control at mesh level
- **Observability**: Metrics, logs, traces collection
- **Gateway API**: Modern ingress specification

**Helm Charts**: `helm/istio/`
- **Chart Versions**:
  - `istio/base`: 1.28.0 (CRDs and cluster configuration)
  - `istio/istiod`: 1.28.0 (control plane)
- **Values File**: `helm/istio/values.yaml`
- **Templates**:
  - `namespace.yaml` - Istio system namespace with injection labels

**Deployed Resources**:
```
Namespace: istio-system
├── Deployment: istiod (1 replica)
├── Service: istiod (discovery)
├── ConfigMap: istio
├── MutatingWebhookConfiguration: istio-sidecar-injector
├── ValidatingWebhookConfiguration: istiod
└── ServiceAccount: istiod

Per-App Resources (in 'app' namespace):
├── VirtualService: my-app
├── DestinationRule: my-app
├── PeerAuthentication: my-app
├── AuthorizationPolicy: my-app
└── EnvoyProxies: Sidecar containers in each pod
```

**How it Works**:
1. istiod acts as service mesh control plane
2. Webhook automatically injects Envoy sidecar proxy in application pods
3. Each pod's sidecar intercepts all network traffic
4. Control plane pushes configuration to all sidecars
5. mTLS certificates automatically managed and rotated
6. Traffic routing and authorization enforced at sidecar level

**Traffic Flow**:
```
Client Pod → Envoy Sidecar (intercepts) → Load balance across destinations
                                           ↓
                                    Backend Pod → Envoy Sidecar
```

**Monitoring**:
```bash
# Check istiod control plane
kubectl get pods -n istio-system

# Check sidecar injection
kubectl get pods -n app -o jsonpath='{.items[].spec.containers[*].name}' | grep istio

# Verify VirtualServices
kubectl get virtualservices -n app
kubectl describe vs my-app -n app

# Check mTLS status
kubectl get peerauthentication -n app
```

---

### Layer 3: Application - my-app (Helm)

**Purpose**: Sample containerized application with full K8s integration

**Namespace**: `app`

**Image**: `kubernetes-platform-stack:latest` (custom Flask app)

**Helm Chart**: `helm/my-app/`
- **Chart Version**: 1.0.0
- **Values File**: `helm/my-app/values.yaml`
- **Templates** (14 files):
  - Core: deployment, service, hpa, rbac, configmap, helpers
  - Istio: virtualservice, destinationrule, peerauthentication, authorizationpolicy
  - Networking: networkpolicy
  - Observability: servicemonitor, poddisruptionbudget

**Deployed Resources**:
```
Namespace: app
├── Deployment: my-app (1-3 replicas via HPA)
│  └── Container: my-app (custom app)
│  └── Container: istio-proxy (Envoy sidecar)
├── Service: my-app (LoadBalancer on port 80→8080)
├── HPA: my-app (min:1, max:5, 80% CPU/Memory threshold)
├── PDB: my-app (minAvailable: 0 for small clusters)
├── ServiceAccount: my-app
├── Role: my-app (pod-level RBAC)
├── RoleBinding: my-app
├── ConfigMap: my-app
├── VirtualService: my-app (Istio routing config)
├── DestinationRule: my-app (load balancing policy)
├── PeerAuthentication: my-app (mTLS STRICT mode)
├── AuthorizationPolicy: my-app (who can access)
├── NetworkPolicy: my-app (pod-level network rules)
└── ServiceMonitor: my-app (Prometheus scraping)
```

**Application Endpoints**:
```
GET  /health           → Health check (always true)
GET  /ready            → Readiness check (startup only)
GET  /status           → Service status
GET  /config           → Configuration
POST /echo             → Echo request body
GET  /metrics          → Prometheus metrics
```

**How it Works**:
1. Deployment manages pod lifecycle (creates 1-3 replicas)
2. Service (LoadBalancer) exposes app externally via port 80
3. Cilium assigns external IP (via BGP announcement)
4. Istio sidecar proxy intercepts all traffic
5. HPA monitors CPU/memory, scales replicas automatically
6. ServiceMonitor tells Prometheus to scrape metrics
7. Network policies control which pods can reach it

**Monitoring**:
```bash
# Check application pods
kubectl get pods -n app

# Check LoadBalancer service
kubectl get svc -n app
# Should show EXTERNAL-IP from BGP pool

# View logs
kubectl logs -n app -l app.kubernetes.io/name=my-app

# Check HPA status
kubectl get hpa -n app

# Verify metrics are scraped
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090/targets → my-app endpoint
```

---

### Layer 4: Observability - Full Stack

#### 4a. Prometheus (v2.48.0)

**Purpose**: Metrics collection and storage

**Namespace**: `monitoring`

**Helm Chart**: `prometheus-community/kube-prometheus-stack`
- **Chart Version**: 65.2.0
- **Values File**: `helm/prometheus/values.yaml`

**Deployed Resources**:
```
Namespace: monitoring
├── Prometheus (StatefulSet)
│  ├── PVC: prometheus-storage (10Gi)
│  ├── ServiceMonitor: watch all services
│  ├── PrometheusRule: alerting rules
│  └── Service: Prometheus (ClusterIP 9090)
├── Grafana (Deployment)
│  ├── Service: Grafana (LoadBalancer 3000)
│  └── ConfigMap: datasources, dashboards
├── AlertManager (StatefulSet)
├── Node Exporter (DaemonSet)
├── Kube State Metrics (Deployment)
└── Prometheus Operator (Deployment)
```

**Data Collection**:
- Scrapes metrics from:
  - kubelet (node metrics)
  - kube-state-metrics (cluster state)
  - Node exporter (system metrics)
  - Cilium (network metrics)
  - Istio (mesh metrics)
  - my-app (application metrics)

**Storage**: 15-day retention, 10Gi PVC

**Access**:
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# http://localhost:9090
```

#### 4b. Grafana (v11.0.0)

**Purpose**: Metrics visualization and dashboards

**Namespace**: `monitoring`

**Features**:
- Pre-configured datasources for Prometheus, Loki, Tempo
- Built-in Kubernetes cluster dashboards
- Custom dashboard for my-app
- Alerting rules
- User management

**Access**:
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# http://localhost:3000
# Username: admin, Password: prom-operator
```

**Default Dashboards**:
- Kubernetes Cluster (nodes, pods, CPU, memory)
- Prometheus (scrape jobs, targets)
- Cilium (network, policy, BGP)
- Istio (traffic, latency, errors)
- Application (custom metrics)

#### 4c. Loki (v3.0.0)

**Purpose**: Log aggregation and querying

**Namespace**: `monitoring`

**Helm Chart**: `grafana/loki-stack`
- **Chart Version**: 2.10.2

**Components**:
- **Loki**: Log aggregator (stores compressed logs)
- **Promtail**: Log shipper (scrapes logs from pods)

**Deployed Resources**:
```
Namespace: monitoring
├── Loki (StatefulSet)
│  ├── PVC: loki-storage (10Gi)
│  └── Service: Loki (ClusterIP 3100)
└── Promtail (DaemonSet)
   └── ConfigMap: scrape config
```

**Log Sources**:
- All pod logs (scraped by Promtail)
- Labeled with pod name, namespace, container
- Queryable from Grafana

**Retention**: Configurable (default: no deletion)

#### 4d. Tempo (v2.3.0)

**Purpose**: Distributed tracing backend

**Namespace**: `monitoring`

**Helm Chart**: `grafana/tempo`
- **Chart Version**: 1.11.2

**Deployed Resources**:
```
Namespace: monitoring
├── Tempo (StatefulSet)
│  ├── PVC: tempo-storage (5Gi)
│  ├── Service: Tempo (gRPC 4317, HTTP 4318)
│  └── ServiceMonitor: Prometheus scraping
└── ConfigMap: tempo config
```

**Receivers**:
- OpenTelemetry OTLP (gRPC 4317, HTTP 4318)
- Jaeger (gRPC 14250, HTTP 14268)

**Integration**:
- Istio sidecars send traces to Tempo
- Grafana queries traces from Tempo
- Correlation with logs and metrics

---

### Layer 5: GitOps Orchestration - ArgoCD (v3.2.0)

**Purpose**: Git-driven continuous deployment and cluster management

**Namespace**: `argocd`

**Helm Chart**: `argoproj/argo-cd`
- **Chart Version**: 7.2.0
- **Values File**: `helm/argocd/values.yaml`

**Deployed Resources**:
```
Namespace: argocd
├── ArgoCD Server (Deployment)
│  ├── Web UI (LoadBalancer port 3000 or 443)
│  ├── API Server
│  └── Service: argocd-server
├── Application Controller (Deployment)
│  └── Reconciles applications
├── Repository Server (Deployment)
│  ├── Pulls from git repos
│  ├── Generates Helm manifests
│  └── Caches for performance
├── Redis (Deployment)
│  └── Cache for performance
├── Dex (Deployment, optional)
│  └── OIDC provider
├── Notifications Controller (Deployment)
│  └── Webhook/Slack integration
├── ApplicationSet Controller (Deployment)
│  └── Multi-environment support
└── Image Updater (Deployment, optional)
   └── Auto-update images
```

**Git Repository Integration**:
```yaml
URL: https://github.com/vietcgi/kubernetes-platform-stack
Branch: main
Path: argocd/
Sync Interval: 30 seconds
Auto-Sync: enabled
```

**Managed Applications**:
1. Cilium (helm/cilium)
2. Istio (helm/istio)
3. Prometheus (helm/prometheus)
4. my-app (helm/my-app)

**How it Works**:
1. Repository Server clones git repo every 30 seconds
2. Parses Helm charts from git
3. Generates Kubernetes manifests
4. Application Controller compares desired vs actual state
5. If drift detected → auto-sync or notify admin
6. Webhook integration for Slack/email notifications

**Access**:
```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
# https://localhost:8080
# Username: admin
# Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

**Key Features**:
- **GitOps Model**: All changes via git commits
- **Diff Preview**: See what will change before applying
- **Automated Sync**: Keep cluster in sync with git
- **Rollback**: Easy rollback to previous state
- **RBAC**: Fine-grained access control
- **Audit Trail**: All sync actions logged

---

## Data Flow & Interactions

### Network Traffic Flow

```
External Request
    ↓
Cilium LoadBalancer (assigns external IP via BGP)
    ↓
Service VirtualIP (10.x.x.x)
    ↓
Cilium eBPF (load balances to pod IPs)
    ↓
Pod's Istio Sidecar (Envoy proxy)
    ↓
Application Container (my-app)
    ↓
Response (encrypted with mTLS if pod-to-pod)
```

### Observability Data Flow

```
Application Pods (my-app)
    ├─ Metrics (Prometheus format)
    │   ↓
    │   ServiceMonitor (scrape config)
    │   ↓
    │   Prometheus (storage)
    │   ↓
    │   Grafana (visualization)
    │
    ├─ Logs (stdout/stderr)
    │   ↓
    │   Promtail (shipper)
    │   ↓
    │   Loki (storage)
    │   ↓
    │   Grafana (query UI)
    │
    └─ Traces (OpenTelemetry/Jaeger)
        ↓
        Istio Sidecar (OTLP export)
        ↓
        Tempo (storage)
        ↓
        Grafana (trace UI)
```

### GitOps Deployment Flow

```
Developer
    ↓
Git Commit (push to main branch)
    ↓
ArgoCD Repository Server (polls every 30s)
    ↓
Helm Chart Rendering
    ↓
Application Controller (diff desired vs actual)
    ↓
Auto-Sync (if enabled)
    ↓
Kubernetes API
    ↓
Controllers (Deployment, StatefulSet, etc.)
    ↓
Running Pods
    ↓
Notifications (Slack, email if configured)
```

---

## Deployment Order & Dependencies

The deployment script installs components in this specific order to manage dependencies:

```
1. KIND Cluster Creation
   ↓ (cluster ready)
2. Cilium Installation
   ↓ (networking ready)
3. Istio Installation
   ├─ istio-base (CRDs)
   └─ istiod (control plane)
   ↓ (service mesh ready)
4. Prometheus Stack Installation
   ├─ kube-prometheus-stack (Prometheus + Grafana)
   └─ Configuration complete
   ↓ (metrics collection ready)
5. Loki Installation
   ↓ (log aggregation ready)
6. Tempo Installation
   ↓ (tracing ready)
7. ArgoCD Installation
   ↓ (GitOps ready)
8. Application (my-app) Installation
   ↓
Final: Health checks & verification
```

**Total Deployment Time**: 12-15 minutes

---

## Namespace Organization

```
kube-system
├── cilium-* (networking)
├── coredns (DNS)
└── kube-proxy (DISABLED)

istio-system
├── istiod (control plane)
├── istio-ingress-gateway (optional)
└── WebhookConfigurations

monitoring
├── prometheus (StatefulSet)
├── grafana (Deployment)
├── loki (StatefulSet)
├── tempo (StatefulSet)
├── alertmanager (StatefulSet)
├── node-exporter (DaemonSet)
└── kube-state-metrics (Deployment)

argocd
├── argocd-server (Deployment)
├── argocd-application-controller (Deployment)
├── argocd-repo-server (Deployment)
├── argocd-redis (Deployment)
└── argocd-notifications-controller (Deployment)

app
├── my-app (Deployment)
└── my-app-hpa (HorizontalPodAutoscaler)
```

---

## Security Architecture

### Network Security (Cilium)

```
Default: DENY ALL INGRESS
    ↓
Explicit Allow Rules:
├─ DNS (port 53/UDP to kube-dns)
├─ App-to-App (port 8080/TCP)
└─ External Ingress (port 80/443/TCP from host)
```

### Service Mesh Security (Istio)

```
mTLS Mode: STRICT (enforced)
    ↓
All traffic between pods is encrypted
    ↓
Automatic certificate rotation
    ↓
Authorization Policy controls access
```

### Pod Security

```
SecurityContext:
├─ runAsNonRoot: true
├─ runAsUser: 1000
├─ readOnlyRootFilesystem: true
└─ allowPrivilegeEscalation: false
```

---

## High Availability Considerations

### Current Configuration (KIND)

- 1 Control Plane + 1 Worker
- No fault tolerance
- Good for development/testing

### Production Configuration (Recommended)

```
3 Control Planes (Kubernetes)
    ↓
Multiple Cilium agents
    ↓
Multiple Istio replicas
    ↓
3 Prometheus replicas (federation)
    ↓
3 ArgoCD server replicas
    ↓
3+ Worker nodes
    ↓
Pod anti-affinity for all applications
    ↓
PodDisruptionBudgets on all critical apps
```

---

## Scaling Considerations

### Horizontal Scaling

```
Add more Worker nodes → Cilium agent on each → auto-scale pods
    ↓
HPA monitors CPU/Memory → scales my-app replicas
    ↓
Service distributes traffic (Cilium load balancing)
```

### BGP Scaling

```
Multiple nodes announce same LoadBalancer IP
    ↓
BGP route aggregation
    ↓
External router distributes to nearest node
    ↓
ECMP (Equal Cost Multipath) for redundancy
```

---

## Cost & Resource Breakdown

### KIND (Development)

```
Total CPU: ~2 cores
Total Memory: ~4-6 GB
Storage: ~50 GB

Breakdown per component:
├─ Control Plane: 0.5 CPU, 1-2 GB RAM
├─ Worker: 0.5 CPU, 1-2 GB RAM
├─ Cilium: 0.1 CPU, 256 MB RAM
├─ Istio: 0.2 CPU, 512 MB RAM
├─ Prometheus: 0.3 CPU, 1 GB RAM
├─ Loki: 0.1 CPU, 256 MB RAM
├─ Tempo: 0.1 CPU, 256 MB RAM
├─ ArgoCD: 0.2 CPU, 512 MB RAM
└─ my-app: 0.1-0.3 CPU (HPA), 128-512 MB RAM
```

### Production (Cloud)

```
Total: 2-4 cores per node × 3-10 nodes
Memory: 4-8 GB per node × 3-10 nodes

Cilium: 10% CPU, 5% Memory (highly efficient)
Istio: 15% CPU, 10% Memory
Prometheus: 20% CPU, 20% Memory (depends on scrape targets)
Loki: 10% CPU, 15% Memory
Tempo: 10% CPU, 10% Memory
ArgoCD: 10% CPU, 10% Memory
Applications: 25% CPU, 30% Memory
```

---

## Upgrade Paths

### Single Component Upgrade

```bash
# Upgrade Cilium
helm upgrade cilium ./helm/cilium -n kube-system

# Upgrade Istio
helm upgrade istiod ./helm/istio -n istio-system

# Upgrade Prometheus
helm upgrade prometheus ./helm/prometheus -n monitoring

# Upgrade my-app
helm upgrade my-app ./helm/my-app -n app
```

### Zero-Downtime Upgrade

```
1. Update git branch with new versions
2. ArgoCD detects changes
3. Progressive rollout via deployment strategy
4. HPA maintains availability during upgrade
5. Canary deployment (optional via ArgoCD)
```

---

## Disaster Recovery

### Backup Points

```
Persistent Data:
├─ etcd (Kubernetes state) - on control plane
├─ Prometheus (metrics) - 10Gi PVC
├─ Loki (logs) - 10Gi PVC
└─ Tempo (traces) - 5Gi PVC

Ephemeral Data:
├─ Redis (can be recreated)
└─ ArgoCD state (can be recreated from git)
```

### Recovery Procedures

```
Prometheus data loss:
→ Restart Prometheus pod, metrics re-scraped in 15 days

Loki data loss:
→ Restart Loki pod, logs collected going forward

Tempo data loss:
→ Restart Tempo pod, traces collected going forward

etcd corruption:
→ Restore from backup or rebuild with new control plane
```

---

## Summary

This architecture provides:

✅ **Modular Design**: Each layer is independent
✅ **Modern Stack**: Latest versions of all components
✅ **Cloud-Native**: Works on any Kubernetes
✅ **Secure**: Multiple layers of security (network, mTLS, RBAC)
✅ **Observable**: Comprehensive metrics, logs, traces
✅ **Scalable**: Auto-scaling and high availability ready
✅ **GitOps**: Everything managed via git
✅ **Production-Ready**: All components proven at scale

For detailed deployment and operations, see:
- `HELM_MIGRATION.md` - Migration guide
- `REFACTORING_SUMMARY.md` - Refactoring details
- `deploy.sh` - Automated deployment script
