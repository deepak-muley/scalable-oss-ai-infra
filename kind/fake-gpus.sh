#!/usr/bin/env bash
# Advertise fake nvidia.com/gpu capacity on nodes labelled nvidia.com/gpu.present=true.
# Pods can request GPUs and the scheduler/Kueue account for them; containers
# get no real device. Re-run after a node restart (kubelet resets status).
set -euo pipefail
COUNT="${1:-4}"
for node in $(kubectl get nodes -l nvidia.com/gpu.present=true -o name); do
  echo "fake GPUs: ${node} -> ${COUNT}"
  kubectl patch "${node}" --subresource=status --type=json \
    -p "[{\"op\":\"add\",\"path\":\"/status/capacity/nvidia.com~1gpu\",\"value\":\"${COUNT}\"}]"
done
kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
