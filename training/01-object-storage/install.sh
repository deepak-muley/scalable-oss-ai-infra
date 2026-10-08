#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
MINIO_ROOT_USER="${MINIO_ROOT_USER:-labadmin}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-$(openssl rand -hex 16)}"

log "Installing MinIO"
kubectl create namespace mlops --dry-run=client -o yaml | kubectl apply -f -
helm repo add minio https://charts.min.io/ --force-update
helm upgrade --install minio minio/minio \
  --namespace mlops $(ver_flag "$MINIO_CHART_VERSION") \
  --set rootUser="${MINIO_ROOT_USER}" --set rootPassword="${MINIO_ROOT_PASSWORD}" \
  -f "${HERE}/values.yaml" --wait

log "Distributing minio-creds secret"
for ns in mlops training llm-serving evaluation; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$ns" create secret generic minio-creds \
    --from-literal=AWS_ACCESS_KEY_ID="${MINIO_ROOT_USER}" \
    --from-literal=AWS_SECRET_ACCESS_KEY="${MINIO_ROOT_PASSWORD}" \
    --from-literal=AWS_ENDPOINT_URL="http://minio.mlops.svc.cluster.local:9000" \
    --from-literal=MLFLOW_S3_ENDPOINT_URL="http://minio.mlops.svc.cluster.local:9000" \
    --dry-run=client -o yaml | kubectl apply -f -
done
echo "MinIO root user: ${MINIO_ROOT_USER}  (password stored in secret mlops/minio-creds)"
