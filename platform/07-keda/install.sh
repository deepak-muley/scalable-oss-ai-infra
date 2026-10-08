#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Installing KEDA"
helm repo add kedacore https://kedacore.github.io/charts --force-update
helm upgrade --install keda kedacore/keda \
  --namespace keda --create-namespace \
  $(ver_flag "$KEDA_VERSION") --wait
