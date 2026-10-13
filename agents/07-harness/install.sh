#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
log "A2A agent card"
kubectl apply -f "${HERE}/../namespace.yaml"
kubectl apply -f "${HERE}/agent-card.yaml"
echo "Card: kubectl -n agents port-forward svc/sre-agent-card 8080:8080"
echo "Then: AGENT_CARD_URL=http://127.0.0.1:8080/.well-known/agent-card.json python3 handoff.py"
echo "Local harness check (no cluster): python3 compare_harnesses.py"
