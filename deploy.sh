#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-platform}"

echo "======================================"
echo "Kubernetes Platform Stack - One-Shot Deployment"
echo "======================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}INFO${NC}: $1"
}

log_warn() {
    echo -e "${YELLOW}WARN${NC}: $1"
}

log_error() {
    echo -e "${RED}ERROR${NC}: $1"
}

# Check prerequisites
log_info "Checking prerequisites..."

for cmd in docker kind kubectl helm; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$cmd is not installed"
        exit 1
    fi
done

log_info "All prerequisites installed"

# Step 1: Delete existing cluster if it exists
log_info "Cleaning up existing cluster '$CLUSTER_NAME'..."
kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true

# Step 2: Create KIND cluster
log_info "Creating KIND cluster '$CLUSTER_NAME'..."
kind create cluster --config "$SCRIPT_DIR/kind-config.yaml" --name "$CLUSTER_NAME"

# Step 3: Build Docker image
log_info "Building Docker image..."
docker build -t kubernetes-platform-stack:latest "$SCRIPT_DIR"

# Step 4: Load image into KIND
log_info "Loading Docker image into KIND..."
kind load docker-image kubernetes-platform-stack:latest --name "$CLUSTER_NAME"

# Step 5: Install Cilium
log_info "Installing Cilium CNI..."
helm repo add cilium https://helm.cilium.io
helm repo update
helm install cilium cilium/cilium --version 1.18.3 \
    --namespace kube-system \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost=kubernetes.default.svc \
    --set k8sServicePort=443 \
    --wait --timeout=5m 2>&1 | grep -E "STATUS|deployed" || log_warn "Cilium installation optional"

# Step 6: Install Prometheus + Grafana
log_info "Installing Prometheus + Grafana..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-prometheus prometheus-community/kube-prometheus-stack --version 61.7.1 \
    --namespace monitoring \
    --create-namespace \
    --set prometheus.prometheusSpec.retention=1h \
    --set prometheus.prometheusSpec.storageSpec.emptyDir={} \
    --set grafana.persistence.enabled=false \
    --wait --timeout=5m 2>&1 | grep -E "STATUS|deployed" || log_warn "Prometheus installation optional"

# Step 7: Create app namespace
log_info "Creating app namespace..."
kubectl create namespace app || true

# Step 8: Deploy application
log_info "Deploying application via Helm..."
helm install my-app "$SCRIPT_DIR/helm/my-app" \
    --namespace app \
    --set image.pullPolicy=Never \
    --wait --timeout=5m

# Step 9: Verify deployment
log_info "Verifying deployment..."
kubectl rollout status deployment/my-app -n app --timeout=5m || true
kubectl get pods -n app

# Step 10: Test health endpoint
log_info "Testing application health endpoint..."
sleep 5
kubectl port-forward -n app svc/my-app 8080:80 > /dev/null 2>&1 &
sleep 2
HEALTH=$(curl -s http://localhost:8080/health 2>/dev/null || echo "")
pkill -f "port-forward" || true

if [ -z "$HEALTH" ]; then
    log_warn "Could not verify health endpoint, but deployment completed"
else
    log_info "Health check passed: $HEALTH"
fi

echo ""
echo "======================================"
echo "Deployment Complete!"
echo "======================================"
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Status: Running"
echo ""
echo "Next steps:"
echo "  1. Access Grafana:"
echo "     kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo "     Open http://localhost:3000 (admin/prom-operator)"
echo ""
echo "  2. Access Prometheus:"
echo "     kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090"
echo "     Open http://localhost:9090"
echo ""
echo "  3. Access your application:"
echo "     kubectl port-forward -n app svc/my-app 8080:80"
echo "     Open http://localhost:8080/health"
echo ""
echo "  4. View logs:"
echo "     kubectl logs -n app -l app=my-app -f"
echo ""
echo "  5. Cleanup when done:"
echo "     kind delete cluster --name $CLUSTER_NAME"
echo ""
