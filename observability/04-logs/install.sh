#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
helm repo add grafana https://grafana.github.io/helm-charts --force-update

log "Installing Loki (single binary)"
helm upgrade --install loki grafana/loki \
  --namespace observability $(ver_flag "${LOKI_CHART_VERSION:-}") \
  -f "${HERE}/loki-values.yaml" --wait --timeout 10m

log "Installing Grafana Alloy (DaemonSet log collector)"
helm upgrade --install alloy grafana/alloy \
  --namespace observability $(ver_flag "${ALLOY_CHART_VERSION:-}") \
  -f "${HERE}/alloy-values.yaml" --wait

kubectl apply -f "${HERE}/grafana-datasource-loki.yaml"
