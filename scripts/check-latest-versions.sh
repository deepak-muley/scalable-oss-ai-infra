#!/usr/bin/env bash
# Print latest upstream versions next to the pins in versions.env.
set -uo pipefail
source "$(dirname "$0")/../versions.env"
row() { printf '%-28s pinned=%-10s latest=%s\n' "$1" "${2:-<latest>}" "$3"; }
helm_latest() { helm search repo "$1" -o json 2>/dev/null | sed -n 's/.*"version":"\([^"]*\)".*/\1/p' | head -1; }
gh_latest() { curl -fsSL "https://api.github.com/repos/$1/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p'; }

helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1
helm repo add metallb https://metallb.github.io/metallb >/dev/null 2>&1
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia >/dev/null 2>&1
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1
helm repo add kedacore https://kedacore.github.io/charts >/dev/null 2>&1
helm repo add kuberay https://ray-project.github.io/kuberay-helm/ >/dev/null 2>&1
helm repo add vllm https://vllm-project.github.io/production-stack >/dev/null 2>&1
helm repo update >/dev/null 2>&1

row cilium "$CILIUM_VERSION" "$(helm_latest cilium/cilium)"
row metallb "$METALLB_VERSION" "$(helm_latest metallb/metallb)"
row cert-manager "$CERT_MANAGER_VERSION" "$(helm_latest jetstack/cert-manager)"
row gpu-operator "$GPU_OPERATOR_VERSION" "$(helm_latest nvidia/gpu-operator)"
row kube-prometheus-stack "$KUBE_PROMETHEUS_STACK_VERSION" "$(helm_latest prometheus-community/kube-prometheus-stack)"
row keda "$KEDA_VERSION" "$(helm_latest kedacore/keda)"
row kuberay-operator "$KUBERAY_VERSION" "$(helm_latest kuberay/kuberay-operator)"
row vllm-stack "$VLLM_STACK_CHART_VERSION" "$(helm_latest vllm/vllm-stack)"
row lws "$LWS_VERSION" "$(gh_latest kubernetes-sigs/lws)"
row kueue "$KUEUE_VERSION" "$(gh_latest kubernetes-sigs/kueue)"
row envoy-gateway "$ENVOY_GATEWAY_VERSION" "$(gh_latest envoyproxy/gateway)"
row envoy-ai-gateway "$AI_GATEWAY_VERSION" "$(gh_latest envoyproxy/ai-gateway)"
row gateway-api-inference-ext "$GATEWAY_API_INFERENCE_EXTENSION_VERSION" "$(gh_latest kubernetes-sigs/gateway-api-inference-extension)"
row kubeflow-trainer "$KUBEFLOW_TRAINER_VERSION" "$(gh_latest kubeflow/trainer)"
echo "vLLM image latest: $(gh_latest vllm-project/vllm)   LMCache: $(gh_latest LMCache/LMCache)"
