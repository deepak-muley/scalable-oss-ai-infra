#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
log "AgentBlueprint CRD"
kubectl apply -f "${HERE}/../namespace.yaml"
kubectl apply -f "${HERE}/crd.yaml"
kubectl wait --for=condition=Established "crd/agentblueprints.agents.lab.example" --timeout=60s
kubectl apply -f "${HERE}/sre-agent.yaml"
echo "kubectl -n agents get agentblueprints"
echo "${HERE}/render.sh"
