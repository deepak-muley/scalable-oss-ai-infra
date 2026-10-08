#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Installing kube-prometheus-stack"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  $(ver_flag "$KUBE_PROMETHEUS_STACK_VERSION") \
  -f "$(dirname "$0")/values.yaml" --wait --timeout 10m
kubectl apply -f "$(dirname "$0")/podmonitor-vllm.yaml"
kubectl apply -f "$(dirname "$0")/podmonitor-envoy.yaml"
