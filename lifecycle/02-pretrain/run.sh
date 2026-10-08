#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
NUM_NODES="${NUM_NODES:-1}"
GPUS_PER_NODE="${GPUS_PER_NODE:-1}"
RUN_NAME="${RUN_NAME:-gpt125m-r1}"        # same RUN_NAME => resume from latest checkpoint
MAX_STEPS="${MAX_STEPS:-2000}"
PEAK_TFLOPS="${PEAK_TFLOPS:-312}"          # bf16 dense peak of YOUR GPU (A100=312, H100=989)

log "Pretrain ${RUN_NAME}: ${NUM_NODES} node(s) x ${GPUS_PER_NODE} GPU, ${MAX_STEPS} steps"
kubectl -n training create configmap pretrain-script --from-file="${HERE}/pretrain.py" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n training delete trainjob pretrain-gpt125m --ignore-not-found
sed -e "s/numNodes: NUM_NODES/numNodes: ${NUM_NODES}/" \
    -e "s/nvidia.com\/gpu: GPUS_PER_NODE/nvidia.com\/gpu: ${GPUS_PER_NODE}/" \
    -e "s/RUN_NAME_VALUE/${RUN_NAME}/" -e "s/MAX_STEPS_VALUE/${MAX_STEPS}/" \
    -e "s/PEAK_TFLOPS_VALUE/${PEAK_TFLOPS}/" \
    "${HERE}/trainjob-pretrain.yaml" | kubectl apply -f -
echo "watch: kubectl -n training get trainjob,workloads ; MLflow experiment 'pretrain'"
