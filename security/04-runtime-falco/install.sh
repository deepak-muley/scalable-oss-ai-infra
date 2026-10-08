#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Installing Falco + Falcosidekick UI"
helm repo add falcosecurity https://falcosecurity.github.io/charts --force-update
helm upgrade --install falco falcosecurity/falco \
  --namespace security --create-namespace $(ver_flag "$FALCO_VERSION") \
  -f "$(dirname "$0")/values.yaml" --wait --timeout 10m
