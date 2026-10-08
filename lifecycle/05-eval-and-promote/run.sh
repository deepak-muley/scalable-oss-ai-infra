#!/usr/bin/env bash
# Usage: run.sh <model-name> <version>     e.g. run.sh qwen2.5-0.5b-grpo-gsm8k v1
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME="${1:?model name (s3://models/<name>/...)}"
VERSION="${2:?version}"
MAX_LEN="${MAX_LEN:-4096}"
TASK="${TASK:-gsm8k}"
LIMIT="${LIMIT:-200}"
BASELINE_URL="${BASELINE_URL:-http://vllm-router-service.llm-serving.svc.cluster.local/v1/chat/completions}"
BASELINE_MODEL="${BASELINE_MODEL:-Qwen/Qwen2.5-1.5B-Instruct}"

render() {
  sed -e "s|MODEL_NAME_VALUE|${NAME}|g" -e "s|MODEL_VERSION_VALUE|${VERSION}|g" \
      -e "s|MAX_LEN_VALUE|${MAX_LEN}|g" -e "s|TASK_VALUE|${TASK}|g" -e "s|LIMIT_VALUE|${LIMIT}|g" \
      -e "s|BASELINE_URL_VALUE|${BASELINE_URL}|g" -e "s|BASELINE_MODEL_VALUE|${BASELINE_MODEL}|g" "$1"
}

log "1/4 sync s3://models/${NAME}/${VERSION} -> model-cache"
kubectl -n llm-serving delete job sync-model --ignore-not-found
render "${HERE}/sync-model-job.yaml" | kubectl apply -f -
kubectl -n llm-serving wait --for=condition=complete job/sync-model --timeout=30m

log "2/4 deploy candidate"
render "${HERE}/candidate-vllm.yaml" | kubectl apply -f -
kubectl apply -f "${HERE}/candidate-backend.yaml"
kubectl -n llm-serving rollout restart deploy/vllm-candidate
kubectl -n llm-serving rollout status deploy/vllm-candidate --timeout=20m

log "3/4 eval gate: ${TASK} (limit ${LIMIT}) candidate vs ${BASELINE_MODEL}"
kubectl -n evaluation delete job eval-gate --ignore-not-found
render "${HERE}/eval-gate-job.yaml" | kubectl apply -f -
kubectl -n evaluation wait --for=condition=complete job/eval-gate --timeout=2h

log "4/4 result"
kubectl -n evaluation logs job/eval-gate | grep '^GATE_RESULT'
echo "Promote with: ${HERE}/promote.sh [--canary <pct>] [--tolerance 0.01]"
