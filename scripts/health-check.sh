#!/bin/bash
# Health check utility functions for cluster monitoring
# Sourced by deploy.sh during bootstrap monitoring phase

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if nodes are ready
check_node_health() {
  local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)
  local total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

  if [ "$ready_nodes" -eq "$total_nodes" ] && [ "$total_nodes" -gt 0 ]; then
    return 0
  else
    return 1
  fi
}

# Check if an ArgoCD application is synced
check_argocd_app_sync() {
  local app_name=$1
  local synced=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.operationState.phase}' 2>/dev/null)
  local sync_status=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)

  if [ "$sync_status" = "Synced" ]; then
    return 0
  else
    return 1
  fi
}

# Check if an ArgoCD application is healthy
check_argocd_app_health() {
  local app_name=$1
  local health=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)

  if [ "$health" = "Healthy" ]; then
    return 0
  else
    return 1
  fi
}

# Check pod health in a namespace by label selector
check_pod_health() {
  local namespace=$1
  local label_selector=$2

  # Get total pods matching selector
  local total=$(kubectl get pods -n "$namespace" -l "$label_selector" --no-headers 2>/dev/null | wc -l)

  # Get ready pods matching selector
  local ready=$(kubectl get pods -n "$namespace" -l "$label_selector" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

  if [ "$total" -gt 0 ] && [ "$ready" -eq "$total" ]; then
    return 0
  else
    return 1
  fi
}

# Get status of an ArgoCD application
get_app_status() {
  local app_name=$1

  local sync_status=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
  local health_status=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
  local revision=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.sync.revision}' 2>/dev/null | cut -c1-7)

  local sync_icon=$([ "$sync_status" = "Synced" ] && echo "✓" || echo "✗")
  local health_icon=$([ "$health_status" = "Healthy" ] && echo "✓" || echo "✗")

  printf "${BLUE}%-20s${NC} Sync: ${BLUE}%-10s${NC} [${sync_icon}] Health: ${BLUE}%-10s${NC} [${health_icon}] Rev: %s\n" \
    "$app_name" "$sync_status" "$health_status" "$revision"
}

# Get pod count in namespace
get_pod_count() {
  local namespace=$1

  local running=$(kubectl get pods -n "$namespace" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
  local total=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l)

  if [ "$total" -gt 0 ]; then
    local status_icon=$([ "$running" -eq "$total" ] && echo "✓" || echo "⚠")
    printf "${BLUE}%-20s${NC} Pods: ${GREEN}%d${NC}/${YELLOW}%d${NC} [${status_icon}]\n" \
      "$namespace" "$running" "$total"
  fi
}

# Monitor app sync with timeout
monitor_app_sync() {
  local app_name=$1
  local timeout=${2:-600}  # Default 10 minutes
  local start_time=$(date +%s)
  local end_time=$((start_time + timeout))

  echo -ne "Waiting for $app_name to sync..."

  while [ $(date +%s) -lt $end_time ]; do
    local sync_status=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)

    if [ "$sync_status" = "Synced" ]; then
      echo -e " ${GREEN}✓${NC}"
      return 0
    fi

    echo -ne "."
    sleep 5
  done

  echo -e " ${RED}✗ (timeout)${NC}"
  return 1
}

# Wait for all apps in a specific sync status
wait_for_app_status() {
  local namespace=$1
  local expected_status=$2
  local timeout=${3:-600}
  local start_time=$(date +%s)
  local end_time=$((start_time + timeout))

  while [ $(date +%s) -lt $end_time ]; do
    local synced_count=$(kubectl get applications -n "$namespace" -o jsonpath='{range .items[*]}{.status.sync.status}{"\n"}{end}' 2>/dev/null | grep -c "^${expected_status}$" || true)
    local total_count=$(kubectl get applications -n "$namespace" --no-headers 2>/dev/null | wc -l)

    if [ "$total_count" -gt 0 ] && [ "$synced_count" -eq "$total_count" ]; then
      return 0
    fi

    sleep 5
  done

  return 1
}

# Get detailed application status
get_detailed_app_status() {
  local app_name=$1

  echo ""
  echo "Application: $app_name"
  echo "─────────────────────────────────"

  kubectl get application "$app_name" -n argocd -o yaml | grep -A 5 "status:" | head -20
}

# Continuously monitor all applications
monitor_all_apps() {
  local namespace=${1:-argocd}
  local interval=${2:-10}

  echo "Monitoring all applications in $namespace (updating every ${interval}s):"
  echo ""

  while true; do
    clear
    echo "═══════════════════════════════════════════════════════════════"
    echo "ArgoCD Applications Status ($(date '+%Y-%m-%d %H:%M:%S'))"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    kubectl get applications -n "$namespace" -o wide 2>/dev/null || echo "No applications found"

    echo ""
    echo "───────────────────────────────────────────────────────────────"
    echo "Cluster Nodes:"
    kubectl get nodes -o wide 2>/dev/null

    echo ""
    echo "Next refresh in ${interval}s (Ctrl+C to exit)..."
    sleep "$interval"
  done
}

# Check if cluster is stable (all critical components healthy)
check_cluster_stability() {
  local checks_passed=0
  local checks_total=0

  # Check nodes
  ((checks_total++))
  if check_node_health; then
    ((checks_passed++))
  fi

  # Check ArgoCD
  ((checks_total++))
  if check_argocd_app_health "root-app"; then
    ((checks_passed++))
  fi

  # Check CoreDNS
  ((checks_total++))
  if check_pod_health "kube-system" "k8s-app=kube-dns"; then
    ((checks_passed++))
  fi

  # Check Cilium
  ((checks_total++))
  if check_pod_health "kube-system" "k8s-app=cilium"; then
    ((checks_passed++))
  fi

  # Return success if at least 75% of checks passed
  local threshold=$((checks_total * 75 / 100))
  if [ "$checks_passed" -ge "$threshold" ]; then
    return 0
  else
    return 1
  fi
}

# Get cluster readiness status
get_cluster_status() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║              CLUSTER STATUS REPORT                         ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""

  # Nodes
  echo "Nodes:"
  kubectl get nodes -o wide 2>/dev/null
  echo ""

  # Applications
  echo "Applications:"
  kubectl get applications -n argocd -o wide 2>/dev/null || echo "No applications"
  echo ""

  # Namespaces
  echo "Namespaces:"
  kubectl get ns -o wide 2>/dev/null
  echo ""

  # Critical pods
  echo "Critical Pods (kube-system):"
  kubectl get pods -n kube-system -o wide | grep -E "coredns|cilium|etcd" || echo "No critical pods found"
  echo ""

  # ArgoCD status
  echo "ArgoCD Status:"
  kubectl get deployment -n argocd -o wide 2>/dev/null
  echo ""
}

# Export functions for sourcing
export -f check_node_health
export -f check_argocd_app_sync
export -f check_argocd_app_health
export -f check_pod_health
export -f get_app_status
export -f get_pod_count
export -f monitor_app_sync
export -f wait_for_app_status
export -f get_detailed_app_status
export -f monitor_all_apps
export -f check_cluster_stability
export -f get_cluster_status
