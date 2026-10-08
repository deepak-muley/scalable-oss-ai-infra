#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
kubectl create namespace apps --dry-run=client -o yaml | kubectl apply -f -

if [[ "${DIRECT_TO_ROUTER:-false}" == "true" ]]; then
  BASE_URL="http://vllm-router-service.llm-serving.svc.cluster.local/v1"
else
  SVC=$(kubectl get svc -n envoy-gateway-system \
    -l gateway.envoyproxy.io/owning-gateway-name=ai-gateway,gateway.envoyproxy.io/owning-gateway-namespace=ai-gateway \
    -o jsonpath='{.items[0].metadata.name}')
  [[ -n "$SVC" ]] || { echo "AI gateway Service not found; install gateway/ first or DIRECT_TO_ROUTER=true"; exit 1; }
  BASE_URL="http://${SVC}.envoy-gateway-system.svc.cluster.local/v1"
fi
API_KEY="${OPENAI_API_KEY:-sk-lab-alice-change-me}"

# Key lives in a Secret referenced from values.yaml (never in helm values/history)
kubectl -n apps create secret generic open-webui-openai --from-literal=api-key="${API_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Installing Open WebUI -> ${BASE_URL}"
helm repo add open-webui https://helm.openwebui.com/ --force-update
helm upgrade --install open-webui open-webui/open-webui \
  --namespace apps $(ver_flag "${OPENWEBUI_CHART_VERSION:-}") \
  -f "${HERE}/values.yaml" \
  --set openaiBaseApiUrl="${BASE_URL}" \
  --wait --timeout 10m
