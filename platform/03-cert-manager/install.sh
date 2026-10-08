#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Installing cert-manager ${CERT_MANAGER_VERSION}"
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  $(ver_flag "$CERT_MANAGER_VERSION") \
  --set crds.enabled=true --wait
kubectl apply -f "$(dirname "$0")/selfsigned-issuer.yaml"
