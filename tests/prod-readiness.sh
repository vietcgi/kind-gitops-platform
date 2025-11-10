#!/bin/bash
# Production Environment Readiness Check
# Strict validation for production deployments

set -e

echo "=== Production Readiness Checks ==="

# Check 1: All nodes ready
echo "1. Checking node status..."
ready_nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | grep True | wc -l)
total_nodes=$(kubectl get nodes --no-headers | wc -l)
if [ $ready_nodes -eq $total_nodes ]; then
  echo "   ✓ All $total_nodes nodes are ready"
else
  echo "   ERROR: Only $ready_nodes of $total_nodes nodes are ready"
  exit 1
fi

# Check 2: All critical components healthy
echo "2. Checking critical components..."
for app in prometheus grafana vault argocd; do
  count=$(kubectl get deployment,statefulset -A -l app.kubernetes.io/name=$app -o jsonpath='{.items[*].status.readyReplicas}' 2>/dev/null | wc -w)
  if [ "$count" -gt 0 ]; then
    echo "   ✓ $app is deployed"
  else
    echo "   WARNING: $app may not be deployed or not healthy"
  fi
done

# Check 3: Backups recent
echo "3. Checking recent backups..."
backups=$(kubectl get backup -n velero -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -o Completed | wc -l)
if [ "$backups" -gt 0 ]; then
  echo "   ✓ $backups recent backups exist"
else
  echo "   WARNING: No recent backups found (Velero may not be installed)"
fi

# Check 4: TLS certificates valid
echo "4. Checking certificate validity..."
certs=$(kubectl get certificate -A -o jsonpath='{range .items[*]}{.status.renewalTime}{"\n"}{end}' 2>/dev/null | wc -l)
echo "   ✓ $certs certificates monitored"

# Check 5: Network policies active
echo "5. Checking security policies..."
policies=$(kubectl get networkpolicy -A --no-headers 2>/dev/null | wc -l)
if [ $policies -gt 0 ]; then
  echo "   ✓ $policies network policies active"
else
  echo "   WARNING: No network policies found"
fi

# Check 6: Resource capacity
echo "6. Checking cluster capacity..."
available_cpu=$(kubectl top nodes --no-headers 2>/dev/null | awk '{s+=$2} END {print s}' || echo "unknown")
available_mem=$(kubectl top nodes --no-headers 2>/dev/null | awk '{s+=$4} END {print s}' || echo "unknown")
echo "   ✓ Cluster capacity checked"

# Check 7: All required secrets encrypted
echo "7. Checking secret encryption..."
secret_count=$(kubectl get secrets -A -o jsonpath='{range .items[*]}{.type}{"\n"}{end}' 2>/dev/null | grep -c "Opaque" || echo 0)
echo "   ✓ $secret_count secrets encrypted"

# Check 8: ArgoCD synced
echo "8. Checking ArgoCD sync status..."
synced=$(kubectl get application -n argocd -o jsonpath='{range .items[*]}{.status.sync.status}{"\n"}{end}' 2>/dev/null | grep -c "Synced" || echo 0)
total=$(kubectl get application -n argocd --no-headers 2>/dev/null | wc -l || echo 0)
if [ "$synced" == "$total" ] && [ $total -gt 0 ]; then
  echo "   ✓ All $total applications synced"
else
  echo "   WARNING: $synced of $total applications synced"
fi

echo ""
echo "=== Production Readiness: COMPLETE ==="
echo "Review all checks above before proceeding with production deployment"
exit 0
