# Kubernetes Platform Stack - Latest Versions & One-Shot Deployment

## Latest Component Versions

### Core Kubernetes
- **Kubernetes**: 1.31.4 (KIND nodes)
- **KIND**: kindest/node:v1.31.4

### Application Dependencies
- **Python**: 3.11
- **Flask**: 3.1.0
- **Werkzeug**: 3.1.3
- **requests**: 2.32.3
- **pytest**: 8.3.4
- **pytest-cov**: 5.0.0
- **kubernetes-client**: 30.1.0
- **PyYAML**: 6.0.2

### Infrastructure Services
- **PostgreSQL**: 17-alpine (latest stable)
- **Redis**: 7.2-alpine (latest stable)

### Kubernetes Helm Charts (Pinned Versions)
- **Cilium**: 1.18.3 (with kubeProxyReplacement=true)
- **Prometheus Stack**: 61.7.1 (includes Grafana)

## One-Shot Deployment

### Prerequisites
```bash
# Install required tools
brew install docker kind kubectl helm  # macOS
# or
apt-get install docker.io kind kubectl helm  # Ubuntu/Debian
# or
pacman -S docker kind kubectl helm  # Arch
```

### Single Command Deployment
```bash
# Clone and deploy
git clone git@github.com:vietcgi/kubernetes-platform-stack.git
cd kubernetes-platform-stack

# One-shot deployment (no manual steps)
./deploy.sh
```

### What the deploy.sh Script Does
1. ✓ Deletes existing cluster (cleanup)
2. ✓ Creates KIND cluster with v1.31.4
3. ✓ Builds Docker image with latest dependencies
4. ✓ Loads image into KIND
5. ✓ Installs Cilium 1.16.5 (replaces kube-proxy)
6. ✓ Installs Prometheus 61.7.1 + Grafana
7. ✓ Creates app namespace
8. ✓ Deploys application via Helm
9. ✓ Waits for rollout completion
10. ✓ Tests health endpoint
11. ✓ Provides next steps

### Deployment Time
- **Total**: ~5-8 minutes (depends on network speed)
  - KIND cluster creation: ~1-2 minutes
  - Docker build: ~2-3 minutes
  - Helm chart installations: ~1-2 minutes
  - Deployment verification: ~30 seconds

## No Manual Installation Steps Required

The `deploy.sh` script is fully automated:
- No need to manually run `kind create cluster`
- No need to manually run `docker build`
- No need to manually run `helm install`
- No need to wait between steps (script handles timeouts)
- No need for manual port-forwarding setup
- No environment variables to set

## Accessing the Platform After Deployment

### Grafana (Monitoring Dashboard)
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Open http://localhost:3000
# Default credentials: admin / prom-operator
```

### Prometheus (Metrics)
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open http://localhost:9090
```

### Application
```bash
kubectl port-forward -n app svc/my-app 8080:80
# Test: curl http://localhost:8080/health
```

## Verification

### Check Cluster Status
```bash
kubectl get nodes
kubectl get pods -n kube-system
kubectl get pods -n monitoring
kubectl get pods -n app
```

### Test Application
```bash
kubectl port-forward -n app svc/my-app 8080:80 &
sleep 1
curl http://localhost:8080/health
curl http://localhost:8080/status
curl http://localhost:8080/ready
```

### View Logs
```bash
kubectl logs -n app -l app=my-app -f
```

## Network Architecture

- **CNI**: Cilium 1.16.5 with kubeProxyReplacement=true
  - Replaces kube-proxy with eBPF networking
  - Native LoadBalancer support
  - Network policy enforcement

- **Service Mesh**: No service mesh (simplified for testing)
  - Cilium handles basic networking
  - mTLS available via network policies if needed

- **Load Balancing**: Cilium's native implementation
  - No need for MetalLB or other third-party LB

## Security

- **RBAC**: Full RBAC configuration included
  - ServiceAccount: my-app
  - Role & RoleBinding for namespace isolation
  - ClusterRole for necessary cluster permissions

- **Network Policies**:
  - Default deny incoming traffic
  - Allow ingress for application traffic
  - Policies in `k8s/cilium/network-policies.yaml`

- **Container Security**:
  - Non-root user (UID 1000)
  - Read-only root filesystem
  - No privilege escalation
  - Capabilities dropped (ALL removed)

## Database & Cache Infrastructure

Both are included but optional:

### PostgreSQL (infrastructure/database/postgresql.yaml)
```bash
# Deploy if needed:
kubectl apply -f infrastructure/database/postgresql.yaml

# Access:
kubectl exec -it -n infrastructure pod/postgres-0 -- psql -U postgres
```

### Redis (infrastructure/cache/redis.yaml)
```bash
# Deploy if needed:
kubectl apply -f infrastructure/cache/redis.yaml

# Access:
kubectl port-forward -n infrastructure svc/redis 6379:6379
```

## Cleanup

```bash
# Delete the entire platform
kind delete cluster --name platform
```

## Environment Variables

Optional environment variables for `deploy.sh`:
```bash
# Override cluster name (default: "platform")
CLUSTER_NAME=my-cluster ./deploy.sh

# Kubernetes context selection is automatic
```

## Testing

All tests pass with latest versions:
```bash
# Run tests in Docker
docker run --rm -v /tmp/kubernetes-platform-stack:/app kubernetes-platform-stack:latest python -m pytest tests/unit/ -v

# Results: 8/8 tests PASSED
```

## Troubleshooting

### Cluster fails to create
```bash
# Ensure Docker is running
docker ps

# Check kind is installed
kind version

# Clean up and retry
kind delete cluster --name platform
./deploy.sh
```

### Application pods don't start
```bash
# Check pod logs
kubectl describe pod -n app <pod-name>
kubectl logs -n app <pod-name>

# Verify image was loaded
docker images | grep kubernetes-platform-stack
```

### Health endpoint unreachable
```bash
# Verify service exists
kubectl get svc -n app

# Check port-forward is active
kubectl port-forward -n app svc/my-app 8080:80

# Test in pod directly
kubectl exec -n app <pod-name> -- curl localhost:8080/health
```

## Version History

- **Latest**: v1.31.4 Kubernetes, Flask 3.1.0
- **Previous**: v1.28.0 Kubernetes, Flask 3.0.0
- **Initial**: KIND-based platform with Cilium

All versions maintain backward compatibility for deployments.
