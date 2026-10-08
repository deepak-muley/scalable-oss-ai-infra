#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
log "Installing OpenCost"
helm repo add opencost https://opencost.github.io/opencost-helm-chart --force-update
helm upgrade --install opencost opencost/opencost \
  --namespace opencost --create-namespace $(ver_flag "${OPENCOST_CHART_VERSION:-}") \
  -f "${HERE}/opencost-values.yaml" --wait
kubectl apply -f "${HERE}/recording-rules-cost.yaml"
kubectl apply -f "${HERE}/dashboard-ai-lab-cost.yaml"
