#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Installing Argo CD ${ARGOCD_CHART_VERSION:-<latest>}"
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  $(ver_flag "${ARGOCD_CHART_VERSION:-}") \
  -f "$(dirname "$0")/values.yaml" --wait --timeout 10m
echo "admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
echo "Next: kubectl apply -f $(dirname "$0")/../02-app-of-apps/root-app.yaml"
