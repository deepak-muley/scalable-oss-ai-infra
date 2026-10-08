#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
GPUS="${GPUS:-2}"
MODEL="${MODEL:-Qwen/Qwen2.5-0.5B-Instruct}"
OUT_NAME="${OUT_NAME:-qwen2.5-0.5b-grpo-gsm8k}"
EPOCHS="${EPOCHS:-3}"
# Pin these together. VERIFY the tag exists on Docker Hub (verlai/verl) and
# matches the git ref — veRL images encode their vLLM/torch versions in the tag.
VERL_IMAGE="${VERL_IMAGE:-verlai/verl:app-verl0.5-vllm0.9.1-mcore0.12.2-te2.2}"
VERL_REF="${VERL_REF:-v0.5.0}"

log "GRPO ${MODEL} on GSM8K with ${GPUS} GPU(s) -> s3://models/${OUT_NAME}/v1"
kubectl apply -f "${HERE}/rl-checkpoints-pvc.yaml"
kubectl -n training delete rayjob rl-grpo-gsm8k --ignore-not-found
sed -e "s|VERL_IMAGE_VALUE|${VERL_IMAGE}|g" -e "s|VERL_REF|${VERL_REF}|g" \
    -e "s|MODEL_VALUE|${MODEL}|g" -e "s|OUT_NAME_VALUE|${OUT_NAME}|g" \
    -e "s|GPUS_VALUE|${GPUS}|g" -e "s|EPOCHS_VALUE|${EPOCHS}|g" \
    "${HERE}/rayjob-grpo.yaml" | kubectl apply -f -
echo "watch: kubectl -n training logs -f job/rl-grpo-gsm8k"
