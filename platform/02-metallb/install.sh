#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Installing MetalLB ${METALLB_VERSION}"
helm repo add metallb https://metallb.github.io/metallb --force-update
helm upgrade --install metallb metallb/metallb \
  --namespace metallb-system --create-namespace \
  $(ver_flag "$METALLB_VERSION") --wait
echo "Now edit and apply: kubectl apply -f $(dirname "$0")/ip-pool.yaml"
