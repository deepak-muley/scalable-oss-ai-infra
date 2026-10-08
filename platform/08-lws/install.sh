#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Installing LeaderWorkerSet ${LWS_VERSION}"
helm upgrade --install lws oci://registry.k8s.io/lws/charts/lws \
  --namespace lws-system --create-namespace \
  $(ver_flag "$LWS_VERSION") --wait
