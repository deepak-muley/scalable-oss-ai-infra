#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
DRIVER_ENABLED="${DRIVER_ENABLED:-false}"   # true = operator installs the driver
log "Installing NVIDIA GPU Operator ${GPU_OPERATOR_VERSION} (driver.enabled=${DRIVER_ENABLED})"
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update
helm upgrade --install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator --create-namespace \
  $(ver_flag "$GPU_OPERATOR_VERSION") \
  --set driver.enabled="${DRIVER_ENABLED}" \
  -f "$(dirname "$0")/values.yaml" --wait --timeout 15m
kubectl get nodes -L nvidia.com/gpu.product,nvidia.com/gpu.count,nvidia.com/gpu.memory
