#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

log "Installing Grafana Tempo (single binary)"
helm repo add grafana https://grafana.github.io/helm-charts --force-update
helm upgrade --install tempo grafana/tempo \
  --namespace observability $(ver_flag "${TEMPO_CHART_VERSION:-}") \
  -f "${HERE}/tempo-values.yaml" --wait

log "Installing OpenTelemetry Collector"
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts --force-update
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --namespace observability $(ver_flag "${OTEL_COLLECTOR_VERSION:-}") \
  -f "${HERE}/otel-collector-values.yaml" --wait

kubectl apply -f "${HERE}/grafana-datasource-tempo.yaml"
echo "Traces endpoint for apps: http://otel-collector.observability.svc.cluster.local:4317 (gRPC) / :4318 (HTTP)"
