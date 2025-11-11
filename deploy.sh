#!/bin/bash
set -e

CLUSTER_NAME="${CLUSTER_NAME:-platform}"
MONITORING_DURATION=${MONITORING_DURATION:-1200}  # 20 minutes in seconds
CHECK_INTERVAL=10  # Check every 10 seconds
STARTUP_TIMEOUT=600  # 10 minutes for initial startup

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Health check state file
HEALTH_STATE_FILE="/tmp/cluster_health_state.json"

log_info "Creating KIND cluster..."
kind create cluster --config kind-config.yaml --name "$CLUSTER_NAME"

echo ""
log_info "Phase 1: Install network prerequisites (CoreDNS + Cilium)"
log_info "=========================================================="

log_info "Waiting for API server to be ready..."
kubectl wait --for=condition=available --timeout=$STARTUP_TIMEOUT deployment/coredns -n kube-system 2>/dev/null || true

log_info "Patching CoreDNS with resource limits..."
kubectl patch deployment coredns -n kube-system -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "coredns",
            "resources": {
              "limits": {
                "cpu": "100m",
                "memory": "64Mi"
              },
              "requests": {
                "cpu": "50m",
                "memory": "32Mi"
              }
            }
          }
        ]
      }
    }
  }
}' 2>/dev/null || true

log_info "Waiting for CoreDNS to be ready..."
kubectl wait --for=condition=ready pod -l k8s-app=kube-dns -n kube-system --timeout=$STARTUP_TIMEOUT

echo ""
log_info "Phase 2: Install ArgoCD"
log_info "======================="

log_info "Creating argocd namespace..."
kubectl create namespace argocd 2>/dev/null || true

log_info "Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

log_info "Waiting for ArgoCD server to be ready..."
kubectl wait deployment argocd-server -n argocd \
  --for=condition=Available --timeout=$STARTUP_TIMEOUT

log_info "Waiting for ArgoCD application controller to be ready..."
kubectl wait deployment argocd-application-controller -n argocd \
  --for=condition=Available --timeout=$STARTUP_TIMEOUT 2>/dev/null || true

log_info "Waiting for ArgoCD repo server to be ready..."
kubectl wait deployment argocd-repo-server -n argocd \
  --for=condition=Available --timeout=$STARTUP_TIMEOUT 2>/dev/null || true

echo ""
log_info "Phase 3: Bootstrap GitOps (ArgoCD manages Cilium, CoreDNS, and all apps)"
log_info "========================================================================"

log_info "Applying root Application for GitOps sync..."
kubectl apply -f argocd/bootstrap/root-app.yaml

log_info "Waiting for root-app to start syncing..."
sleep 5

echo ""
log_info "Phase 4: Active Health Monitoring (${MONITORING_DURATION}s / 20 min)"
log_info "========================================================================"
log_info "Monitoring cluster health and app sync status..."
echo ""

# Source health check functions
source ./scripts/health-check.sh

# Initialize monitoring
MONITORING_START=$(date +%s)
MONITORING_END=$((MONITORING_START + MONITORING_DURATION))
CRITICAL_APPS=("root-app" "coredns-config" "cilium")
HEALTHY=true

# Counters
declare -A APP_SYNC_COUNTS
declare -A APP_READY_COUNTS

while [ $(date +%s) -lt $MONITORING_END ]; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - MONITORING_START))
  REMAINING=$((MONITORING_END - CURRENT_TIME))

  ELAPSED_MIN=$((ELAPSED / 60))
  REMAINING_MIN=$((REMAINING / 60))
  REMAINING_SEC=$((REMAINING % 60))

  echo -ne "\r[${ELAPSED_MIN}m] Monitoring in progress... ${REMAINING_MIN}m ${REMAINING_SEC}s remaining"

  # Check cluster health
  check_node_health
  NODE_STATUS=$?

  # Check critical app health
  check_argocd_app_sync "root-app"
  ROOT_APP_SYNCED=$?

  check_argocd_app_sync "coredns-config"
  COREDNS_SYNCED=$?

  check_argocd_app_sync "cilium"
  CILIUM_SYNCED=$?

  check_argocd_app_health "root-app"
  ROOT_APP_HEALTHY=$?

  check_pod_health "kube-system" "k8s-app=kube-dns"
  COREDNS_HEALTHY=$?

  check_pod_health "kube-system" "k8s-app=cilium"
  CILIUM_HEALTHY=$?

  # Accumulate healthy checks
  [ $ROOT_APP_SYNCED -eq 0 ] && ((APP_SYNC_COUNTS["root-app"]++))
  [ $COREDNS_SYNCED -eq 0 ] && ((APP_SYNC_COUNTS["coredns-config"]++))
  [ $CILIUM_SYNCED -eq 0 ] && ((APP_SYNC_COUNTS["cilium"]++))

  [ $ROOT_APP_HEALTHY -eq 0 ] && ((APP_READY_COUNTS["root-app"]++))
  [ $COREDNS_HEALTHY -eq 0 ] && ((APP_READY_COUNTS["coredns-config"]++))
  [ $CILIUM_HEALTHY -eq 0 ] && ((APP_READY_COUNTS["cilium"]++))

  # Determine if critical apps are healthy enough (at least 50% of checks passed)
  if [ $NODE_STATUS -ne 0 ] || [ $ROOT_APP_HEALTHY -ne 0 ]; then
    HEALTHY=false
  fi

  sleep $CHECK_INTERVAL
done

echo -e "\n"
echo "═══════════════════════════════════════════════════════════════════"

# Final health assessment
log_info "Final Health Assessment"
log_info "======================="

get_app_status "root-app"
get_app_status "coredns-config"
get_app_status "cilium"

get_pod_count "argocd"
get_pod_count "kube-system"

# Get overall cluster health
NODES_READY=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)
NODES_TOTAL=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

echo ""
log_success "Cluster bootstrap complete!"
log_success "Nodes ready: ${NODES_READY}/${NODES_TOTAL}"
log_success "Phase 1: CoreDNS configured and managed by ArgoCD"
log_success "Phase 2: ArgoCD deployed and self-managed"
log_success "Phase 3: GitOps bootstrap initiated with root-app"
log_success "Phase 4: Active monitoring completed"

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo ""
log_info "Next steps:"
echo "  1. Monitor ongoing sync status:"
echo "     kubectl get applications -n argocd -w"
echo ""
echo "  2. Check specific app status:"
echo "     kubectl describe application <app-name> -n argocd"
echo ""
echo "  3. View ArgoCD UI:"
echo "     kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo "     Open: https://localhost:8080 (default: admin/generated-password)"
echo ""
echo "  4. Watch all resources syncing:"
echo "     kubectl get all -A -w"
echo ""
