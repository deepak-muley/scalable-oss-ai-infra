#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
log "Agent workload identity + OpenBao policy ConfigMap"
kubectl apply -f "${HERE}/../namespace.yaml"
kubectl apply -f "${HERE}/agent-worker-sa.yaml"
kubectl -n agents create configmap openbao-agent-policy \
  --from-file=prometheus-read.hcl="${HERE}/openbao-policy.hcl" \
  --dry-run=client -o yaml | kubectl apply -f -
if [[ "${INSTALL_SPIRE:-false}" == "true" ]]; then
  log "SPIRE (opt-in). Workload identity for the agent ServiceAccount."
  helm repo add spiffe https://spiffe.github.io/helm-charts --force-update
  helm upgrade --install spire-crds spiffe/spire-crds \
    --namespace spire-system --create-namespace $(ver_flag "${SPIRE_CRDS_VERSION:-}") --wait
  helm upgrade --install spire spiffe/spire \
    --namespace spire-system $(ver_flag "${SPIRE_VERSION:-}") --wait
  echo "SPIRE installed with chart defaults. Confirm the agent-worker SPIFFE ID before relying on it."
else
  echo "SPIRE skipped. Re-run with INSTALL_SPIRE=true to install the SPIRE helm charts."
fi
echo "Token exchange: see README.md and ./exchange.sh"
