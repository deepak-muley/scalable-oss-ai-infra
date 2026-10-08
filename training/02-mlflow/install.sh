#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
log "Installing MLflow"
helm repo add community-charts https://community-charts.github.io/helm-charts --force-update
AK=$(kubectl -n mlops get secret minio-creds -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
SK=$(kubectl -n mlops get secret minio-creds -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
helm upgrade --install mlflow community-charts/mlflow \
  --namespace mlops $(ver_flag "$MLFLOW_CHART_VERSION") \
  -f "$(dirname "$0")/values.yaml" \
  --set artifactRoot.s3.awsAccessKeyId="$AK" \
  --set artifactRoot.s3.awsSecretAccessKey="$SK" --wait
