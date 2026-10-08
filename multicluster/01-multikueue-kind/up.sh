#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
require kind docker
HERE="$(cd "$(dirname "$0")" && pwd)"
export KUBECONFIG="${MC_KUBECONFIG:-/tmp/ai-lab-multicluster.kubeconfig}"
MANAGER=ai-lab-manager
WORKER=ai-lab-worker1
KUEUE_VER="${KUEUE_VERSION:-0.13.4}"

for c in "$MANAGER" "$WORKER"; do
  if ! kind get clusters | grep -qx "$c"; then
    log "Creating kind cluster $c"
    kind create cluster --name "$c" --kubeconfig "$KUBECONFIG"
  fi
done

for c in "$MANAGER" "$WORKER"; do
  log "Installing Kueue ${KUEUE_VER} on $c"
  helm upgrade --install kueue oci://registry.k8s.io/kueue/charts/kueue \
    --kube-context "kind-$c" --namespace kueue-system --create-namespace \
    --version "${KUEUE_VER}" --wait --timeout 10m
done

log "Fake GPUs on the worker"
kubectl config use-context "kind-$WORKER"
kubectl label nodes --all nvidia.com/gpu.present=true --overwrite
"${REPO_ROOT}/kind/fake-gpus.sh" 8

log "Worker queues"
kubectl --context "kind-$WORKER" apply -f "${HERE}/worker-queues.yaml"

log "Storing the worker's INTERNAL kubeconfig in the manager"
kind get kubeconfig --internal --name "$WORKER" > /tmp/ai-lab-worker1-internal.kubeconfig
kubectl --context "kind-$MANAGER" -n kueue-system create secret generic worker1-secret \
  --from-file=kubeconfig=/tmp/ai-lab-worker1-internal.kubeconfig --dry-run=client -o yaml \
  | kubectl --context "kind-$MANAGER" apply -f -
rm -f /tmp/ai-lab-worker1-internal.kubeconfig

log "Manager MultiKueue config + queues"
kubectl --context "kind-$MANAGER" apply -f "${HERE}/manager-multikueue.yaml"
sleep 5
kubectl --context "kind-$MANAGER" get multikueuecluster,admissioncheck,clusterqueue

cat <<MSG

Ready. Next:
  export KUBECONFIG=${KUBECONFIG}
  kubectl --context kind-${MANAGER} create -f ${HERE}/demo-job.yaml
  kubectl --context kind-${WORKER} get pods -n training -w
MSG
