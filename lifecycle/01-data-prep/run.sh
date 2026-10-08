#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
MODE="${MODE:-pretrain}"          # pretrain | sft
N_DOCS="${N_DOCS:-100000}"

log "Data prep MODE=${MODE} N_DOCS=${N_DOCS}"
kubectl -n training create configmap data-prep-script --from-file="${HERE}/prep.py" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n training delete rayjob "data-prep-${MODE}" --ignore-not-found
sed -e "s/MODE_VALUE/${MODE}/g" -e "s/N_DOCS_VALUE/${N_DOCS}/" "${HERE}/rayjob-data-prep.yaml" | kubectl apply -f -
echo "watch: kubectl -n training get rayjob data-prep-${MODE} -w"
