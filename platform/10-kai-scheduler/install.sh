#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Installing KAI Scheduler ${KAI_SCHEDULER_VERSION}"
helm upgrade --install kai-scheduler \
  oci://ghcr.io/kai-scheduler/kai-scheduler/kai-scheduler \
  --namespace kai-scheduler --create-namespace \
  $(ver_flag "$KAI_SCHEDULER_VERSION") \
  -f "$(dirname "$0")/values.yaml" --wait
echo "Edit GPU budgets then: kubectl apply -f $(dirname "$0")/queues.yaml"
echo "Examples: kubectl apply -f $(dirname "$0")/examples/<file>.yaml"
