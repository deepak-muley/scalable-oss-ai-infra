#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
V="${GATEWAY_API_INFERENCE_EXTENSION_VERSION}"

log "Installing Gateway API Inference Extension CRDs ${V}"
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/${V}/manifests.yaml"

log "Deploying vLLM pool members"
kubectl apply -f "${HERE}/vllm-pool-deployment.yaml"

log "Installing InferencePool + Endpoint Picker (EPP)"
helm upgrade --install vllm-qwen-pool \
  oci://registry.k8s.io/gateway-api-inference-extension/charts/inferencepool \
  --namespace llm-serving \
  --version "${V}" \
  --set inferencePool.modelServers.matchLabels.app=vllm-qwen-pool \
  --wait

kubectl apply -f "${HERE}/ai-gateway-route-pool.yaml"
