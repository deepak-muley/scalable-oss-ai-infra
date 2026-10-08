#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Creating namespace workbench (PSA baseline)"
cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: workbench
  labels:
    ai.lab/layer: workbench
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/warn: restricted
YAML
log "Installing JupyterHub"
helm repo add jupyterhub https://hub.jupyter.org/helm-chart/ --force-update
helm upgrade --install jupyterhub jupyterhub/jupyterhub \
  --namespace workbench $(ver_flag "${JUPYTERHUB_CHART_VERSION:-}") \
  -f "$(dirname "$0")/values.yaml" --wait --timeout 15m
