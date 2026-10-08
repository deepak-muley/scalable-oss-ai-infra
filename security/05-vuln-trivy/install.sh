#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Installing Trivy Operator"
helm repo add aqua https://aquasecurity.github.io/helm-charts/ --force-update
helm upgrade --install trivy-operator aqua/trivy-operator \
  --namespace trivy-system --create-namespace $(ver_flag "$TRIVY_OPERATOR_VERSION") \
  -f "$(dirname "$0")/values.yaml" --wait
