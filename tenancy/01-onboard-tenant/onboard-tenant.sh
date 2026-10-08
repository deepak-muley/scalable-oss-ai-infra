#!/usr/bin/env bash
# TENANT=<name> GPU_QUOTA=<n> TOKENS_PER_HOUR=<n> ./onboard-tenant.sh
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
: "${TENANT:?set TENANT=<dns-safe name>}"
[[ "${TENANT}" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || { echo "TENANT must be DNS-safe"; exit 1; }
GPU_QUOTA="${GPU_QUOTA:-2}"
GPU_BORROW_LIMIT="${GPU_BORROW_LIMIT:-${GPU_QUOTA}}"
GPU_CAP=$(( GPU_QUOTA + GPU_BORROW_LIMIT ))
CPU_QUOTA="${CPU_QUOTA:-32}"
MEM_QUOTA="${MEM_QUOTA:-256Gi}"
FAIR_WEIGHT="${FAIR_WEIGHT:-1}"
TOKENS_PER_HOUR="${TOKENS_PER_HOUR:-1000000}"
GROUP_PREFIX="${GROUP_PREFIX:-oidc:}"
DRY_RUN="${DRY_RUN:-false}"

render() {
  sed -e "s|\${TENANT}|${TENANT}|g" \
      -e "s|\${GPU_QUOTA}|${GPU_QUOTA}|g" \
      -e "s|\${GPU_BORROW_LIMIT}|${GPU_BORROW_LIMIT}|g" \
      -e "s|\${GPU_CAP}|${GPU_CAP}|g" \
      -e "s|\${CPU_QUOTA}|${CPU_QUOTA}|g" \
      -e "s|\${MEM_QUOTA}|${MEM_QUOTA}|g" \
      -e "s|\${FAIR_WEIGHT}|${FAIR_WEIGHT}|g" \
      -e "s|\${GROUP_PREFIX}|${GROUP_PREFIX}|g" "$1"
}

ALL=""
for t in namespace quota kueue network rbac; do
  ALL+="$(render "${HERE}/templates/${t}.yaml")"$'\n---\n'
done

if [[ "${DRY_RUN}" == "true" ]]; then echo "${ALL}"; exit 0; fi

log "Onboarding tenant ${TENANT} (GPUs ${GPU_QUOTA} + borrow ${GPU_BORROW_LIMIT}, ${TOKENS_PER_HOUR} tokens/h)"
echo "${ALL}" | kubectl apply -f -

# Tenant registry -> single token-budget policy for all tenants
cat > "${HERE}/../tenants/${TENANT}.env" <<ENV
TENANT=${TENANT}
GPU_QUOTA=${GPU_QUOTA}
TOKENS_PER_HOUR=${TOKENS_PER_HOUR}
ENV
"${HERE}/render-token-budgets.sh" | kubectl apply -f -

# Service API key for the tenant (stored in the gateway's key secret)
if kubectl -n ai-gateway get secret ai-gateway-api-keys >/dev/null 2>&1; then
  KEY="sk-${TENANT}-$(openssl rand -hex 16)"
  kubectl -n ai-gateway patch secret ai-gateway-api-keys --type merge \
    -p "{\"stringData\":{\"${TENANT}-svc\":\"${KEY}\"}}"
  echo "API key for ${TENANT}-svc (shown once): ${KEY}"
  echo "If keys are managed by OpenBao/ESO, store it there instead: bao kv patch secret/ai-lab/gateway-keys ${TENANT}-svc=<key>"
else
  echo "ai-gateway-api-keys secret not found; skipping API key (apply gateway/03-ai-routes/security-policy.yaml)"
fi

cat <<MSG

Tenant ${TENANT} ready:
  namespace     tenant-${TENANT}  (submit jobs with label kueue.x-k8s.io/queue-name=default)
  Keycloak      create group "tenant-${TENANT}" and a user attribute/claim tenant=${TENANT}
  check         kubectl get clusterqueue tenant-${TENANT}; kubectl -n tenant-${TENANT} get resourcequota
MSG
