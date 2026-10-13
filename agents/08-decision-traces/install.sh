#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
log "Agent decision alerts"
kubectl apply -f "${HERE}/../namespace.yaml"
if ! kubectl get crd prometheusrules.monitoring.coreos.com >/dev/null 2>&1; then
  echo "skip: Prometheus Operator CRDs are not installed (platform/06-monitoring)."
  echo "The rule is ${HERE}/prometheus-rule.yaml. Re-run this script after monitoring is up."
  exit 0
fi
kubectl apply -f "${HERE}/prometheus-rule.yaml"
echo "Spans: kubectl -n agents logs deploy/tool-gateway"
echo "Shape: ${HERE}/span-example.json"
