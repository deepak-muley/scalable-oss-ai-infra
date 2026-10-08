#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
kubectl create namespace security --dry-run=client -o yaml | kubectl apply -f -

log "Installing OpenBao (dev mode)"
helm repo add openbao https://openbao.github.io/openbao-helm --force-update
helm upgrade --install openbao openbao/openbao \
  --namespace security $(ver_flag "$OPENBAO_CHART_VERSION") \
  -f "${HERE}/openbao-values.yaml" --wait

log "Installing External Secrets Operator"
helm repo add external-secrets https://charts.external-secrets.io --force-update
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  $(ver_flag "$EXTERNAL_SECRETS_VERSION") --set installCRDs=true --wait

# token ESO uses to read OpenBao (dev root token; use k8s auth in real life)
kubectl -n security create secret generic openbao-token --from-literal=token=root \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${HERE}/cluster-secret-store.yaml"
