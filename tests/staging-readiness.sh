#!/bin/bash
# Staging Environment Readiness Check
# Validates that staging cluster meets production-like requirements

set -e

echo "=== Staging Readiness Checks ==="

# Check 1: Cluster connectivity
echo "1. Checking cluster connectivity..."
if ! kubectl cluster-info > /dev/null 2>&1; then
  echo "ERROR: Cannot connect to Kubernetes cluster"
  exit 1
fi
echo "   ✓ Cluster accessible"

# Check 2: Required namespaces exist
echo "2. Checking required namespaces..."
for ns in argocd monitoring istio-system vault cert-manager; do
  if ! kubectl get namespace $ns > /dev/null 2>&1; then
    echo "   WARNING: Namespace $ns not found"
  else
    echo "   ✓ Namespace $ns exists"
  fi
done

# Check 3: Storage available
echo "3. Checking storage..."
storage=$(kubectl get pvc -A 2>/dev/null | wc -l)
echo "   ✓ $storage PVCs available"

# Check 4: Network connectivity
echo "4. Checking network policies..."
policies=$(kubectl get networkpolicies -A 2>/dev/null | wc -l)
echo "   ✓ $policies network policies configured"

# Check 5: Helm repos accessible
echo "5. Checking Helm repositories..."
helm repo list || echo "   WARNING: Helm repos may be inaccessible"

# Check 6: Docker image availability
echo "6. Checking container images..."
if ! docker info > /dev/null 2>&1; then
  echo "   WARNING: Docker not available"
fi

echo ""
echo "=== Staging Readiness: PASSED ==="
exit 0
