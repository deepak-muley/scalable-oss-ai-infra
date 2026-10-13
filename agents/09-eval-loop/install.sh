#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
log "Skill eval gate"
kubectl apply -f "${HERE}/../namespace.yaml"
kubectl -n agents create configmap skill-eval-src \
  --from-file=eval_trajectories.py="${HERE}/eval_trajectories.py" \
  --from-file=trajectories.jsonl="${HERE}/trajectories.jsonl" \
  --from-file=trajectories-bad.jsonl="${HERE}/trajectories-bad.jsonl" \
  --dry-run=client -o yaml | kubectl apply -f -
if ! kubectl get crd workflowtemplates.argoproj.io >/dev/null 2>&1; then
  echo "skip: WorkflowTemplate CRD is not installed (pipelines/01-argo-workflows)."
  echo "Local gate still runs: python3 ${HERE}/eval_trajectories.py"
  exit 0
fi
kubectl apply -f "${HERE}/rbac.yaml" -f "${HERE}/skill-release-workflowtemplate.yaml"
echo "Add namespace agents to pipelines/01-argo-workflows/values.yaml workflowNamespaces if submit stays Pending."
echo "argo submit -n agents --from workflowtemplate/skill-release --watch"
