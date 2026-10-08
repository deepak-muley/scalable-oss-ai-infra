#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE_MODEL="${BASE_MODEL:-Qwen/Qwen2.5-0.5B}"
OUT_NAME="${OUT_NAME:-qwen2.5-0.5b-sft}"
OUT_VERSION="${OUT_VERSION:-v1}"
LR="${LR:-1e-5}"                      # toy GPT from scratch: try 1e-4

log "SFT ${BASE_MODEL} -> s3://models/${OUT_NAME}/${OUT_VERSION}"
kubectl -n training create configmap sft-script --from-file="${HERE}/sft.py" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n training delete trainjob sft --ignore-not-found
sed -e "s|BASE_MODEL_VALUE|${BASE_MODEL}|" -e "s|OUT_NAME_VALUE|${OUT_NAME}|" \
    -e "s|OUT_VERSION_VALUE|${OUT_VERSION}|" -e "s|LR_VALUE|${LR}|" \
    "${HERE}/trainjob-sft.yaml" | kubectl apply -f -
