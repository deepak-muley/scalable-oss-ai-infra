#!/usr/bin/env bash
# End-to-end checks against the kind lab.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KEY="${KEY:-sk-lab-alice-change-me}"
PORT="${PORT:-8080}"
pass() { printf '\033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$*"; FAILED=1; }
FAILED=0

# On macOS the docker network (LB IPs) is not reachable -> port-forward.
SVC=$(kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=ai-gateway,gateway.envoyproxy.io/owning-gateway-namespace=ai-gateway \
  -o jsonpath='{.items[0].metadata.name}')
kubectl -n envoy-gateway-system port-forward "svc/${SVC}" "${PORT}:80" >/dev/null 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 3
URL="http://localhost:${PORT}"

chat() {  # chat <model> [api-key]
  curl -s -o /tmp/ai-lab-resp.json -w '%{http_code}' "${URL}/v1/chat/completions" \
    -H 'content-type: application/json' -H "x-api-key: ${2:-$KEY}" \
    -d "{\"model\":\"$1\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}],\"max_tokens\":16}" || true
}

echo "--- gateway: ${URL} (svc ${SVC})"
[[ "$(chat Qwen/Qwen2.5-1.5B-Instruct)" == 200 ]] && pass "route Qwen small" || fail "route Qwen small: $(cat /tmp/ai-lab-resp.json)"
[[ "$(chat meta-llama/Llama-3.1-8B-Instruct)" == 200 ]] && pass "route Llama 8B" || fail "route Llama 8B"
[[ "$(chat lab-chat)" == 200 ]] && pass "alias lab-chat -> Qwen (modelNameOverride)" || fail "alias lab-chat"
code=$(chat Qwen/Qwen2.5-1.5B-Instruct sk-wrong); [[ "$code" == 401 || "$code" == 403 ]] && pass "bad API key rejected ($code)" || fail "bad API key got $code"
code=$(chat no-such-model); [[ "$code" != 200 ]] && pass "unknown model rejected ($code)" || fail "unknown model got 200"

if kubectl get inferencepool sim-pool -n llm-serving >/dev/null 2>&1; then
  [[ "$(chat Qwen/Qwen3-8B)" == 200 ]] && pass "InferencePool route (EPP)" || fail "InferencePool route"
fi

echo "--- Kueue quota + preemption demo"
kubectl delete job -n training low-a low-b high-c --ignore-not-found >/dev/null
kubectl apply -f "${HERE}/manifests/kueue-demo.yaml" >/dev/null; sleep 8
kubectl get workloads -n training
kubectl apply -f "${HERE}/manifests/kueue-demo-high.yaml" >/dev/null; sleep 10
kubectl get workloads -n training
if kubectl get workloads -n training -o json | grep -q '"reason": "Preempted"'; then
  pass "high-priority job preempted a low-priority one"
else
  echo "(no preemption observed yet; re-check: kubectl get workloads -n training -w)"
fi
kubectl delete job -n training low-a low-b high-c --ignore-not-found >/dev/null

echo "--- KubeRay"
sed "s|RAY_IMAGE|${RAY_IMAGE:-rayproject/ray:2.46.0-py311$( [[ $(uname -m) == arm64 ]] && echo -aarch64)}|g" \
  "${HERE}/manifests/rayjob-cpu.yaml" | kubectl apply -f - >/dev/null
echo "RayJob submitted: kubectl get rayjob -n training -w   (image pull takes a few minutes)"

if kubectl get scaledobject sim-llama8b -n llm-serving >/dev/null 2>&1; then
  echo "--- KEDA: generating load on Llama sim for 90s (max-num-seqs=2 => queue)"
  end=$((SECONDS+90))
  while (( SECONDS < end )); do
    for _ in $(seq 1 10); do chat meta-llama/Llama-3.1-8B-Instruct >/dev/null & done; wait
  done
  kubectl get deploy sim-llama8b -n llm-serving
  echo "(replicas > 1 means KEDA scaled on vllm:num_requests_waiting)"
fi

exit $FAILED
