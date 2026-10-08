#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
: "${NFS_SERVER:?set NFS_SERVER=<ip of your NFS server>}"
: "${NFS_PATH:?set NFS_PATH=<exported path, e.g. /export/k8s>}"

log "Installing NFS subdir external provisioner -> ${NFS_SERVER}:${NFS_PATH}"
helm repo add nfs-subdir-external-provisioner \
  https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/ --force-update
helm upgrade --install nfs-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace nfs-provisioner --create-namespace \
  $(ver_flag "$NFS_PROVISIONER_VERSION") \
  --set nfs.server="${NFS_SERVER}" \
  --set nfs.path="${NFS_PATH}" \
  -f "$(dirname "$0")/nfs-values.yaml" --wait

if [[ "${INSTALL_LOCAL_PATH:-false}" == "true" ]]; then
  log "Installing rancher local-path-provisioner (RWO, node-local)"
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
fi
