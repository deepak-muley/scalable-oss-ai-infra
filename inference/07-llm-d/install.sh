#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
LLMD_VERSION="${LLMD_VERSION:-v0.2.0}"          # pin; check github.com/llm-d/llm-d/releases
LLMD_DIR="${LLMD_DIR:-${TMPDIR:-/tmp}/llm-d-${LLMD_VERSION}}"   # outside the repo: not committed
NAMESPACE="${NAMESPACE:-llm-d}"
GUIDE="${GUIDE:-}"                               # inference-scheduling | pd-disaggregation | wide-ep-lws
RUN="${RUN:-false}"
require git

if [[ ! -d "${LLMD_DIR}/.git" ]]; then
  log "Cloning llm-d ${LLMD_VERSION}"
  git clone --depth 1 --branch "${LLMD_VERSION}" https://github.com/llm-d/llm-d.git "${LLMD_DIR}"
fi

log "Guides available at ${LLMD_VERSION}:"
ls -1 "${LLMD_DIR}/guides" 2>/dev/null || {
  echo "No guides/ dir at this tag — layout changed; browse ${LLMD_DIR} manually."; exit 1; }

cat <<MSG

Prerequisites (see ${LLMD_DIR}/guides/prereq/ at this tag):
  * client tools: helmfile, helm, kubectl, yq   (guides/prereq/client-setup)
  * a Gateway API provider + GIE CRDs          (guides/prereq/gateway-provider)
    -> you may reuse this lab's Envoy/kgateway setup only if the guide supports it
  * HF token secret in namespace ${NAMESPACE}   (guides document the expected name)

Read:  ${LLMD_DIR}/guides/<guide>/README.md  — commands below are the common
pattern but MUST be checked against the README for ${LLMD_VERSION}.
MSG

if [[ -n "${GUIDE}" && "${RUN}" == "true" ]]; then
  require helmfile
  GDIR="${LLMD_DIR}/guides/${GUIDE}"
  [[ -d "${GDIR}" ]] || { echo "guide ${GUIDE} not found at ${LLMD_VERSION}"; exit 1; }
  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  log "helmfile apply for guide ${GUIDE} in ns ${NAMESPACE}"
  ( cd "${GDIR}" && helmfile apply -n "${NAMESPACE}" )
  kubectl -n "${NAMESPACE}" get pods
fi
