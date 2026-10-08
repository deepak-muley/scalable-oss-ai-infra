# Backups — Velero to MinIO

**What to back up in an AI lab, and what not to:**

| Data | Back up? | Why |
|---|---|---|
| Kubernetes objects (routes, queues, policies, CRs, Secrets) | **yes**, via Velero | rebuilding config by hand after a mistake is slow and error-prone |
| MLflow DB, Keycloak and OpenBao state, Qdrant | **yes** (PVC data) | small, irreplaceable |
| Model weights in `model-cache` PVC | **no** | re-downloadable from HF or your `models` bucket; hundreds of GB |
| Checkpoints, datasets, adapters | already in **S3 (MinIO)** | protect the bucket itself with versioning and replication instead |

Velero stores backups in a MinIO bucket `velero` and can back up PVC
contents with its node agent (file-system backup with Kopia).

> Backing up *into* the same MinIO you're protecting only guards against
> config mistakes, not against losing the storage box. In a real setup point
> the BackupStorageLocation at an off-cluster S3.

```bash
./install.sh
kubectl apply -f schedules.yaml
velero backup create manual-1 --include-namespaces ai-gateway,mlops   # CLI: brew install velero
velero backup describe manual-1 --details
```

## Restore drill (do this, it's the point)

```bash
kubectl delete aigatewayroute lab-models -n ai-gateway       # "oops"
velero restore create --from-backup <backup-name> \
  --include-namespaces ai-gateway --include-resources aigatewayroutes.aigateway.envoyproxy.io
kubectl get aigatewayroute -n ai-gateway
```

Time the drill. Your RTO is what you measured, not what you assumed.
