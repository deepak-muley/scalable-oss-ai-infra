#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
log "gVisor RuntimeClass (handler runsc)"
kubectl apply -f "${HERE}/../namespace.yaml"
kubectl apply -f "${HERE}/runtimeclass.yaml"
echo "RuntimeClass gvisor is registered. Pods stay Pending until runsc is installed on the node."
echo "Example: kubectl apply -f ${HERE}/code-exec-pod.yaml"
echo "Node setup: see README.md (runsc install, then restart containerd)."
