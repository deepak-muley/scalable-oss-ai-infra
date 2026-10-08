#!/usr/bin/env bash
# Bring up the whole lab on kind with simulated GPUs + simulated vLLM.
# Reuses the real component install.sh scripts, so this also tests them.
#
#   ./up.sh                         # default profile
#   WITH_MONITORING=false ./up.sh   # lighter (no Prometheus/Grafana, no KEDA demo)
#   WITH_GIE=true ./up.sh           # + Gateway API Inference Extension demo
#   WITH_TRAINER=true ./up.sh       # + Kubeflow Trainer
#   WITH_SECURITY=true ./up.sh      # + Kyverno (audit), Falco, OpenBao+ESO
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
source "${ROOT}/scripts/lib.sh"
require kind docker

CLUSTER="${CLUSTER:-ai-lab}"
WITH_MONITORING="${WITH_MONITORING:-true}"
WITH_GIE="${WITH_GIE:-false}"
WITH_TRAINER="${WITH_TRAINER:-false}"
WITH_SECURITY="${WITH_SECURITY:-false}"
FAKE_GPUS_PER_NODE="${FAKE_GPUS_PER_NODE:-4}"
# Pin to a released tag if 'latest' isn't published for your platform.
SIM_IMAGE="${SIM_IMAGE:-ghcr.io/llm-d/llm-d-inference-sim:latest}"
case "$(uname -m)" in
  arm64|aarch64) RAY_IMAGE="${RAY_IMAGE:-rayproject/ray:2.46.0-py311-aarch64}" ;;
  *)             RAY_IMAGE="${RAY_IMAGE:-rayproject/ray:2.46.0-py311}" ;;
esac

render() { sed -e "s|SIM_IMAGE|${SIM_IMAGE}|g" -e "s|RAY_IMAGE|${RAY_IMAGE}|g" "$1"; }

# ---------------------------------------------------------------- cluster
if ! kind get clusters | grep -qx "${CLUSTER}"; then
  log "Creating kind cluster ${CLUSTER}"
  kind create cluster --name "${CLUSTER}" --config "${HERE}/kind-config.yaml"
fi
kubectl config use-context "kind-${CLUSTER}"

# ---------------------------------------------------------------- platform
API_SERVER_IP="${CLUSTER}-control-plane" CILIUM_VALUES="${HERE}/cilium-values-kind.yaml" \
  "${ROOT}/platform/00-cilium/install.sh"
kubectl wait --for=condition=Ready nodes --all --timeout=5m

log "Cilium LB-IPAM pool from the kind docker network"
SUBNET=$(docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' | tr ' ' '\n' | grep -m1 '\.')
PREFIX=$(echo "${SUBNET}" | cut -d. -f1-2)
cat <<YAML | kubectl apply -f -
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata: {name: kind-pool}
spec:
  blocks: [{start: "${PREFIX}.255.200", stop: "${PREFIX}.255.250"}]
---
apiVersion: cilium.io/v2alpha1
kind: CiliumL2AnnouncementPolicy
metadata: {name: kind-l2}
spec:
  loadBalancerIPs: true
  interfaces: ["^eth[0-9]+"]
YAML

"${HERE}/fake-gpus.sh" "${FAKE_GPUS_PER_NODE}"
"${ROOT}/platform/01-namespaces/install.sh"
"${ROOT}/platform/03-cert-manager/install.sh"
if [[ "${WITH_MONITORING}" == "true" ]]; then
  "${ROOT}/platform/06-monitoring/install.sh"
fi
"${ROOT}/platform/07-keda/install.sh"
"${ROOT}/platform/08-lws/install.sh"
"${ROOT}/platform/09-kueue/install.sh"
kubectl apply -f "${ROOT}/platform/09-kueue/queues.yaml"

# ---------------------------------------------------------------- gateway
WITH_INFERENCE_POOL="${WITH_GIE}" "${ROOT}/gateway/01-envoy-gateway/install.sh"
"${ROOT}/gateway/02-envoy-ai-gateway/install.sh"
kubectl apply -f "${ROOT}/gateway/03-ai-routes/gateway.yaml"
kubectl apply -f "${ROOT}/gateway/03-ai-routes/security-policy.yaml"

# ---------------------------------------------------------------- "models"
log "Deploying simulated vLLM servers (${SIM_IMAGE})"
render "${HERE}/manifests/sim-models.yaml" | kubectl apply -f -
kubectl apply -f "${HERE}/manifests/ai-routes-kind.yaml"
if [[ "${WITH_MONITORING}" == "true" ]]; then
  kubectl apply -f "${HERE}/manifests/keda-sim.yaml"
fi

if [[ "${WITH_GIE}" == "true" ]]; then
  log "Gateway API Inference Extension demo"
  V="${GATEWAY_API_INFERENCE_EXTENSION_VERSION}"
  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/${V}/manifests.yaml"
  render "${HERE}/manifests/gie-sim-pool.yaml" | kubectl apply -f -
  helm upgrade --install sim-pool \
    oci://registry.k8s.io/gateway-api-inference-extension/charts/inferencepool \
    --namespace llm-serving --version "${V}" \
    --set inferencePool.modelServers.matchLabels.app=sim-pool --wait
fi

# ---------------------------------------------------------------- training
"${ROOT}/training/04-kuberay/install.sh"
if [[ "${WITH_TRAINER}" == "true" ]]; then
  "${ROOT}/training/03-kubeflow-trainer/install.sh"
fi

if [[ "${WITH_SECURITY}" == "true" ]]; then
  "${ROOT}/security/02-secrets-openbao-eso/install.sh"
  "${ROOT}/security/03-policy-kyverno/install.sh"
  "${ROOT}/security/04-runtime-falco/install.sh"
fi

log "Waiting for simulated models"
kubectl -n llm-serving rollout status deploy/sim-qwen-small --timeout=5m
kubectl -n llm-serving rollout status deploy/sim-llama8b --timeout=5m

cat <<MSG

Lab is up.  Next:
  ${HERE}/test.sh            # end-to-end checks (gateway, auth, routing, Kueue, Ray)
  ${HERE}/down.sh            # delete the cluster
MSG
