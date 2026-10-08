#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Installing Envoy AI Gateway CRDs ${AI_GATEWAY_VERSION}"
helm upgrade --install aieg-crd oci://docker.io/envoyproxy/ai-gateway-crds-helm \
  --namespace envoy-ai-gateway-system --create-namespace \
  $(ver_flag "$AI_GATEWAY_VERSION")

log "Installing Envoy AI Gateway controller ${AI_GATEWAY_VERSION}"
helm upgrade --install aieg oci://docker.io/envoyproxy/ai-gateway-helm \
  --namespace envoy-ai-gateway-system --create-namespace \
  $(ver_flag "$AI_GATEWAY_VERSION") --wait

# Envoy Gateway must reconnect to the (now running) extension server.
kubectl rollout restart -n envoy-gateway-system deployment/envoy-gateway
kubectl rollout status  -n envoy-gateway-system deployment/envoy-gateway
