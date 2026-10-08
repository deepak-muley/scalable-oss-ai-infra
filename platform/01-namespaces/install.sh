#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Creating lab namespaces"
kubectl apply -f "$(dirname "$0")/namespaces.yaml"
