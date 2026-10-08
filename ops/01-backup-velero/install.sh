#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
AK=$(kubectl -n mlops get secret minio-creds -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
SK=$(kubectl -n mlops get secret minio-creds -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)

log "Creating bucket 'velero' in MinIO"
kubectl -n mlops run velero-bucket --rm -i --restart=Never --image=amazon/aws-cli:2.17.0 \
  --env AWS_ACCESS_KEY_ID="$AK" --env AWS_SECRET_ACCESS_KEY="$SK" -- \
  --endpoint-url http://minio.mlops.svc.cluster.local:9000 s3 mb s3://velero || true

kubectl create namespace velero --dry-run=client -o yaml | kubectl apply -f -
kubectl -n velero create secret generic velero-minio --from-literal=cloud="[default]
aws_access_key_id=${AK}
aws_secret_access_key=${SK}" --dry-run=client -o yaml | kubectl apply -f -

log "Installing Velero"
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts --force-update
helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero $(ver_flag "${VELERO_CHART_VERSION:-}") \
  -f "${HERE}/values.yaml" --wait --timeout 10m
