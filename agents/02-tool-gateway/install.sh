#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
log "OPA + tool gateway"
kubectl apply -f "${HERE}/../namespace.yaml"
kubectl -n agents create configmap opa-policy \
  --from-file=authz.rego="${HERE}/policy.rego" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n agents create configmap tool-gateway-src \
  --from-file=tool_gateway.py="${HERE}/tool_gateway.py" \
  --dry-run=client -o yaml | kubectl apply -f -
sed -e "s|OPA_VERSION|${OPA_VERSION}|g" "${HERE}/opa.yaml" | kubectl apply -f -
kubectl apply -f "${HERE}/gateway.yaml"
echo "Gateway: kubectl -n agents port-forward svc/tool-gateway 8090:8090"
echo "OPA:     kubectl -n agents port-forward svc/opa 8181:8181"
echo "Kill:    OPA_URL=http://127.0.0.1:8181 ./kill.sh on"
