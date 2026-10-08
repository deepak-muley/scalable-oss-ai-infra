#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Installing Kyverno"
helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace $(ver_flag "$KYVERNO_VERSION") --wait
kubectl apply -f "$(dirname "$0")/policies/"
