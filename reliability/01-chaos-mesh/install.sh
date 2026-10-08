#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
SOCKET="${RUNTIME_SOCKET:-/run/containerd/containerd.sock}"
log "Installing Chaos Mesh (runtime=containerd socket=${SOCKET})"
helm repo add chaos-mesh https://charts.chaos-mesh.org --force-update
helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh --create-namespace $(ver_flag "${CHAOS_MESH_VERSION:-}") \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath="${SOCKET}" \
  --set dashboard.securityMode=false \
  --wait --timeout 10m
kubectl get crd | grep chaos-mesh.org
