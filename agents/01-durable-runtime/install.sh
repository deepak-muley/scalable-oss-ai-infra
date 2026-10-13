#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
log "Temporal dev server + agent worker (namespace agents)"
kubectl apply -f "${HERE}/../namespace.yaml"
kubectl -n agents create configmap agent-worker-src \
  --from-file=worker.py="${HERE}/worker.py" \
  --dry-run=client -o yaml | kubectl apply -f -
sed -e "s|TEMPORAL_CLI_VERSION|${TEMPORAL_CLI_VERSION}|g" \
  "${HERE}/temporal.yaml" | kubectl apply -f -
echo "UI:  kubectl -n agents port-forward svc/temporal 8233:8233   # http://localhost:8233"
echo "Run: kubectl -n agents exec deploy/agent-worker -- python /app/worker.py start \"Which pods are running?\""
