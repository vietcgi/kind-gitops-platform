# Kubernetes Platform Stack

Production Kubernetes platform built with KIND, Cilium, Istio, ArgoCD, and observability stack.

## What This Is

A working Kubernetes platform that runs entirely in KIND (Kubernetes in Docker). Built to test infrastructure patterns, networking policies, and service mesh configurations without spinning up expensive cloud infrastructure.

Includes:
- Cilium CNI with eBPF networking and native LoadBalancer
- Istio for service mesh with mTLS
- ArgoCD for GitOps
- Prometheus, Grafana, Loki, Tempo for observability
- Network policies and security configurations
- Full CI/CD pipeline in GitHub Actions

## Quick Start

**Prerequisites**: Install `kind`, `docker`, `kubectl`, `helm`

```bash
# Clone and navigate
git clone git@github.com:vietcgi/kubernetes-platform-stack.git
cd kubernetes-platform-stack

# Create KIND cluster (1 control plane + 2 workers)
kind create cluster --config kind-config.yaml --name platform

# Verify cluster
kubectl cluster-info
kubectl get nodes  # Should show 3 nodes ready

# Build Docker image
docker build -t kubernetes-platform-stack:latest .

# Load image into KIND
kind load docker-image kubernetes-platform-stack:latest --name platform

# Create app namespace
kubectl create namespace app

# Deploy application via Helm
helm install my-app helm/my-app \
  --namespace app \
  --set image.pullPolicy=Never \
  --wait

# Verify deployment
kubectl get pods -n app        # Should show 2 running pods
kubectl get svc -n app         # Should show LoadBalancer service

# Test the app
kubectl port-forward -n app svc/my-app 8080:80 &
curl http://localhost:8080/health
# Output: {"status":"healthy",...}
```

**Done!** Your Kubernetes platform is running.

## What's Included

### Networking
- **Cilium CNI** - Uses eBPF instead of traditional networking. Handles pod-to-pod communication, network policies, and LoadBalancer services.
- **Network Policies** - Default deny incoming traffic, with explicit allow rules for specific services.
- **LoadBalancer** - Cilium's native implementation, no need for MetalLB.

### Service Mesh
- **Istio** - mTLS between services, traffic policies, authorization rules.
- **Encryption** - Pod traffic encrypted with WireGuard.

### Observability
- **Prometheus** - Scrapes metrics from Cilium, Istio, and application endpoints.
- **Grafana** - Dashboards for cluster and application metrics.
- **Loki** - Aggregates logs from all pods.
- **Tempo** - Traces requests across services.

### Deployment
- **Helm Chart** - Standard Helm chart for the application.
- **Kubernetes Manifests** - Network policies and Istio configurations.
- **ArgoCD** - Ready to set up GitOps-style deployments.

## Running Tests

```bash
# Unit tests
pytest tests/unit/ -v

# Integration tests (requires running cluster)
pytest tests/integration/ -v

# All tests
pytest tests/ -v
```

## GitHub Actions Pipeline

Runs 15 stages:
1. Code quality checks
2. Docker image build and scan
3. KIND cluster creation
4. Component installation (Cilium, Istio, Prometheus, etc.)
5. Application deployment
6. Network connectivity tests
7. Security policy validation
8. Integration tests
9. Observability checks
10. Performance metrics

Takes about 12-15 minutes end-to-end.

## Why KIND Instead of EKS?

- **Cost**: Free vs $150-200/month
- **Speed**: Cluster ready in 30 seconds vs 15 minutes
- **Reproducibility**: Same setup for everyone
- **Testing**: Run full platform locally before pushing to prod

The platform works the same way in KIND as it would in production Kubernetes.

## Directory Structure

```
.
├── .github/workflows/
│   └── platform.yml              # CI/CD pipeline
├── helm/my-app/                  # Helm chart for app
├── k8s/
│   ├── cilium/                   # Network policies
│   ├── istio/                    # Service mesh config
│   ├── argocd/                   # GitOps setup
│   └── crossplane/               # Infrastructure code
├── src/app.py                    # Flask application
├── tests/
│   ├── unit/                     # Unit tests
│   └── integration/              # K8s tests
├── Dockerfile
├── requirements.txt
└── README.md
```

## Local Development

### Accessing Services

```bash
# Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# http://localhost:9090

# Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# http://localhost:3000

# Loki
kubectl port-forward -n monitoring svc/loki 3100:3100

# ArgoCD (if installed)
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

### Checking Logs

```bash
# Application logs
kubectl logs -n app -l app=my-app -f

# Cilium
kubectl logs -n kube-system -l k8s-app=cilium -f

# Istio
kubectl logs -n istio-system -l app=istiod -f
```

### Debugging Network Policies

```bash
# See applied policies
kubectl get ciliumnetworkpolicies -n app
kubectl describe cnp -n app

# Check connectivity
kubectl run debug --image=busybox --rm -it --restart=Never -- sh
# Inside pod: wget -O- http://my-app:8080/health
```

## Common Tasks

### Add a New Service

1. Create manifests in `k8s/`
2. Update Helm chart in `helm/my-app/`
3. Add tests in `tests/`
4. Commit and push - CI/CD handles the rest

### Modify Network Policies

Edit `k8s/cilium/network-policies.yaml`, deploy with:
```bash
kubectl apply -f k8s/cilium/
```

### Update Application

Change code in `src/app.py`, rebuild Docker image:
```bash
docker build -t my-app:latest .
kind load docker-image my-app:latest
```

## Troubleshooting

**Pods not starting**
```bash
kubectl describe pod -n app
kubectl logs -n app <pod-name>
```

**Service not accessible**
```bash
kubectl get svc -n app
kubectl exec -n app <pod> -- curl localhost:8080/health
```

**Network policies blocking traffic**
```bash
# Check policies
kubectl get networkpolicies -n app
# Temporarily remove
kubectl delete networkpolicies --all -n app
```

**Cluster issues**
```bash
# Check node status
kubectl get nodes
kubectl describe node <node-name>

# Restart cluster
kind delete cluster --name platform
kind create cluster --config .github/kind-config.yaml
```

## Technologies

- **KIND** - Local Kubernetes clusters
- **Cilium** - Container networking and security
- **Istio** - Service mesh
- **ArgoCD** - Continuous deployment
- **Crossplane** - Infrastructure automation
- **Prometheus** - Metrics
- **Grafana** - Dashboards
- **Loki** - Log aggregation
- **Tempo** - Tracing

## License

MIT
