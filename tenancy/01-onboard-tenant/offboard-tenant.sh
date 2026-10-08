#!/usr/bin/env bash
# TENANT=<name> ./offboard-tenant.sh   — deletes the namespace (and all workloads/PVCs in it!)
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
: "${TENANT:?set TENANT=<name>}"
CONFIRM="${CONFIRM:-}"
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "This deletes namespace tenant-${TENANT} with ALL its workloads and PVCs."
  echo "Re-run with CONFIRM=yes to proceed."; exit 1
fi
log "Offboarding tenant ${TENANT}"
kubectl delete localqueue default -n "tenant-${TENANT}" --ignore-not-found
kubectl delete clusterqueue "tenant-${TENANT}" --ignore-not-found
kubectl delete namespace "tenant-${TENANT}" --ignore-not-found
rm -f "${HERE}/../tenants/${TENANT}.env"
"${HERE}/render-token-budgets.sh" | kubectl apply -f -
# remove the tenant's service key if present (json-patch fails harmlessly if absent)
kubectl -n ai-gateway patch secret ai-gateway-api-keys --type json \
  -p "[{\"op\":\"remove\",\"path\":\"/data/${TENANT}-svc\"}]" 2>/dev/null || true
echo "Done. Remember to remove Keycloak group tenant-${TENANT} and any OpenBao key."
