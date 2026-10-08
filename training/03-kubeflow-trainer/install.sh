#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
V="${KUBEFLOW_TRAINER_VERSION}"
log "Installing Kubeflow Trainer ${V} (controller + JobSet)"
kubectl apply --server-side -k "https://github.com/kubeflow/trainer.git/manifests/overlays/manager?ref=${V}"
kubectl -n kubeflow-system wait --for=condition=Available deploy --all --timeout=5m
log "Installing default ClusterTrainingRuntimes"
kubectl apply --server-side -k "https://github.com/kubeflow/trainer.git/manifests/overlays/runtimes?ref=${V}"
kubectl get clustertrainingruntimes
