#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
RAW="https://raw.githubusercontent.com/envoyproxy/ai-gateway/${AI_GATEWAY_VERSION}"

fetch() { log "fetch $1"; curl -fsSL "${RAW}/$1" -o "${HERE}/$2"; }

fetch manifests/envoy-gateway-values.yaml envoy-gateway-values.yaml
VALUES=(-f "${HERE}/envoy-gateway-values.yaml")

if [[ "${WITH_INFERENCE_POOL:-false}" == "true" ]]; then
  fetch examples/inference-pool/envoy-gateway-values-addon.yaml values-addon-inference-pool.yaml
  VALUES+=(-f "${HERE}/values-addon-inference-pool.yaml")
fi

if [[ "${WITH_RATELIMIT:-false}" == "true" ]]; then
  # Redis for Envoy's global rate-limit service
  kubectl create namespace redis-system --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "${HERE}/redis.yaml"
  fetch examples/token_ratelimit/envoy-gateway-values-addon.yaml values-addon-ratelimit.yaml
  VALUES+=(-f "${HERE}/values-addon-ratelimit.yaml")
fi

log "Installing Envoy Gateway ${ENVOY_GATEWAY_VERSION}"
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --namespace envoy-gateway-system --create-namespace \
  $(ver_flag "$ENVOY_GATEWAY_VERSION") "${VALUES[@]}" --wait
