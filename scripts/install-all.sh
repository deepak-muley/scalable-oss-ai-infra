#!/usr/bin/env bash
# Install the full lab on a REAL GPU cluster, layer by layer.
# Each layer can be run on its own:  ./scripts/install-all.sh platform
# Read docs/04-install-runbook.md first — some steps need your input
# (API server IP, NFS server, IP pool, HF token).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAYER="${1:-all}"

platform() {
  [[ "${SKIP_CILIUM:-false}" == "true" ]] || "${ROOT}/platform/00-cilium/install.sh"     # needs API_SERVER_IP
  "${ROOT}/platform/01-namespaces/install.sh"
  [[ "${USE_METALLB:-false}" == "true" ]] && "${ROOT}/platform/02-metallb/install.sh"
  "${ROOT}/platform/03-cert-manager/install.sh"
  "${ROOT}/platform/04-storage/install.sh"                                             # needs NFS_SERVER/NFS_PATH
  "${ROOT}/platform/05-gpu-operator/install.sh"
  "${ROOT}/platform/06-monitoring/install.sh"
  "${ROOT}/platform/07-keda/install.sh"
  "${ROOT}/platform/08-lws/install.sh"
  "${ROOT}/platform/09-kueue/install.sh"
  echo ">> remember: edit+apply platform/00-cilium/lb-ipam.yaml (or 02-metallb/ip-pool.yaml) and platform/09-kueue/queues.yaml"
}
gateway() {
  "${ROOT}/gateway/01-envoy-gateway/install.sh"
  "${ROOT}/gateway/02-envoy-ai-gateway/install.sh"
  kubectl apply -f "${ROOT}/gateway/03-ai-routes/gateway.yaml"
}
inference() {
  kubectl apply -f "${ROOT}/inference/01-model-storage/model-cache-pvc.yaml"
  "${ROOT}/inference/04-production-stack/install.sh"
  kubectl apply -f "${ROOT}/gateway/03-ai-routes/backends.yaml" -f "${ROOT}/gateway/03-ai-routes/ai-gateway-route.yaml"
}
training() {
  "${ROOT}/training/01-object-storage/install.sh"
  "${ROOT}/training/02-mlflow/install.sh"
  "${ROOT}/training/03-kubeflow-trainer/install.sh"
  "${ROOT}/training/04-kuberay/install.sh"
}
security() {
  "${ROOT}/security/01-identity-keycloak/install.sh"
  "${ROOT}/security/02-secrets-openbao-eso/install.sh"
  "${ROOT}/security/03-policy-kyverno/install.sh"
  "${ROOT}/security/04-runtime-falco/install.sh"
  "${ROOT}/security/05-vuln-trivy/install.sh"
}

case "$LAYER" in
  platform|gateway|inference|training|security) "$LAYER" ;;
  all) platform; security; gateway; inference; training ;;
  *) echo "usage: $0 [all|platform|security|gateway|inference|training]"; exit 1 ;;
esac
