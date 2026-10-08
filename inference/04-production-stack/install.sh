#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
VALUES="${VALUES:-values-1gpu.yaml}"
EXTRA=()
[[ "${SHARED_KV:-false}" == "true" ]] && EXTRA=(-f "${HERE}/values-shared-kv.yaml")

log "Installing vLLM production-stack with ${VALUES} ${EXTRA[*]:-}"
helm repo add vllm https://vllm-project.github.io/production-stack --force-update
helm upgrade --install vllm vllm/vllm-stack \
  --namespace llm-serving --create-namespace \
  $(ver_flag "$VLLM_STACK_CHART_VERSION") \
  -f "${HERE}/${VALUES}" "${EXTRA[@]}" --timeout 20m
