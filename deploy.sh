#!/bin/bash
set -e

CLUSTER_NAME="${CLUSTER_NAME:-platform}"

echo "Creating KIND cluster..."
kind create cluster --config kind-config.yaml --name "$CLUSTER_NAME"

echo "Patching CoreDNS (KIND cluster DNS)..."
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
}'

echo "Installing ArgoCD..."
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for ArgoCD server..."
kubectl wait deployment argocd-server -n argocd \
  --for=condition=Available --timeout=300s

echo "Bootstrapping from git..."
kubectl apply -f argocd/bootstrap/root-app.yaml

echo ""
echo "✓ Cluster bootstrapped!"
echo "✓ ArgoCD is managing itself and all applications"
echo ""
echo "Monitor progress:"
echo "  kubectl get applications -n argocd -w"
echo ""
