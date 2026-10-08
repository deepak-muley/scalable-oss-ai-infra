#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
# With kube-proxy gone, Cilium must reach the API server directly.
: "${API_SERVER_IP:?set API_SERVER_IP=<control plane IP / VIP / hostname>}"
API_SERVER_PORT="${API_SERVER_PORT:-6443}"
VALUES="${CILIUM_VALUES:-${HERE}/values.yaml}"

log "Installing Cilium ${CILIUM_VERSION} (k8sServiceHost=${API_SERVER_IP}:${API_SERVER_PORT})"
helm repo add cilium https://helm.cilium.io/ --force-update
helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  $(ver_flag "$CILIUM_VERSION") \
  --set k8sServiceHost="${API_SERVER_IP}" \
  --set k8sServicePort="${API_SERVER_PORT}" \
  -f "${VALUES}" --wait --timeout 10m

kubectl -n kube-system rollout status ds/cilium --timeout=5m
echo "Next: edit and apply ${HERE}/lb-ipam.yaml"
