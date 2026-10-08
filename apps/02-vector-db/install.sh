#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
kubectl create namespace apps --dry-run=client -o yaml | kubectl apply -f -
log "Installing Qdrant"
helm repo add qdrant https://qdrant.github.io/qdrant-helm --force-update
helm upgrade --install qdrant qdrant/qdrant \
  --namespace apps $(ver_flag "${QDRANT_CHART_VERSION:-}") \
  -f "$(dirname "$0")/values.yaml" --wait
