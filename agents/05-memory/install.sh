#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
log "Agent memory: Valkey (working) + Postgres (episodes)"
kubectl apply -f "${HERE}/../namespace.yaml"
kubectl -n agents create configmap agent-memory-schema \
  --from-file=01-schema.sql="${HERE}/schema.sql" \
  --dry-run=client -o yaml | kubectl apply -f -
sed -e "s|VALKEY_VERSION|${VALKEY_VERSION}|g" \
    -e "s|POSTGRES_VERSION|${POSTGRES_VERSION}|g" \
    "${HERE}/memory.yaml" | kubectl apply -f -
echo "Working:  kubectl -n agents exec deploy/valkey -- valkey-cli SET agent:sre-agent:working:thread-1 'which pods are queueing' EX 3600"
echo "Episodes: kubectl -n agents exec deploy/postgres -- psql -U agent -d agent_memory -c '\\dt'"
