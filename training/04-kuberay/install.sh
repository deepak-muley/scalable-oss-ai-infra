#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Installing KubeRay operator ${KUBERAY_VERSION}"
helm repo add kuberay https://ray-project.github.io/kuberay-helm/ --force-update
helm upgrade --install kuberay-operator kuberay/kuberay-operator \
  --namespace kuberay-system --create-namespace \
  $(ver_flag "$KUBERAY_VERSION") -f "$(dirname "$0")/values.yaml" --wait
