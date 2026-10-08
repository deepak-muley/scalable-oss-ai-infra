#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Installing Keycloak (dev mode)"
kubectl create namespace security --dry-run=client -o yaml | kubectl apply -f -
helm repo add codecentric https://codecentric.github.io/helm-charts --force-update
helm upgrade --install keycloak codecentric/keycloakx \
  --namespace security $(ver_flag "$KEYCLOAK_CHART_VERSION") \
  -f "$(dirname "$0")/values.yaml" --wait --timeout 10m
