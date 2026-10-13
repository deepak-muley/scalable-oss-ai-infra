#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
log "Skill manifests"
kubectl apply -f "${HERE}/../namespace.yaml"
kubectl -n agents create configmap agent-skills \
  --from-file=cluster-read="${HERE}/cluster-read/SKILL.md" \
  --from-file=cost-watch="${HERE}/cost-watch/SKILL.md" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n agents label configmap agent-skills \
  agents.lab/version=0.1.0 \
  --overwrite
echo "Skills: kubectl -n agents get configmap agent-skills -o jsonpath='{.data}'"
