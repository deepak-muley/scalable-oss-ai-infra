#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Installing node-problem-detector with a GPU XID kernel-log monitor"
helm repo add deliveryhero https://charts.deliveryhero.io/ --force-update
helm upgrade --install node-problem-detector deliveryhero/node-problem-detector \
  --namespace gpu-health --create-namespace $(ver_flag "${NPD_CHART_VERSION:-}") \
  -f "$(dirname "$0")/npd-values.yaml" --wait
