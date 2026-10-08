#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Installing Kueue ${KUEUE_VERSION}"
helm upgrade --install kueue oci://registry.k8s.io/kueue/charts/kueue \
  --namespace kueue-system --create-namespace \
  $(ver_flag "$KUEUE_VERSION") -f "$(dirname "$0")/values.yaml" --wait
echo "Edit quotas then: kubectl apply -f $(dirname "$0")/queues.yaml"
