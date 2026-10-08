#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
log "Installing Argo Workflows ${ARGO_WORKFLOWS_CHART_VERSION:-<latest>}"
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm upgrade --install argo-workflows argo/argo-workflows \
  --namespace argo --create-namespace \
  $(ver_flag "${ARGO_WORKFLOWS_CHART_VERSION:-}") \
  -f "${HERE}/values.yaml" --wait
kubectl apply -f "${HERE}/rbac.yaml"
echo "UI: kubectl -n argo port-forward svc/argo-workflows-server 2746:2746"
