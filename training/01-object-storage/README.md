# Object storage (S3 API) — datasets, checkpoints, artifacts, adapters

Frontier-lab pattern: **everything durable goes to object storage** — raw
and tokenized datasets, training checkpoints, eval results, model/adapter
"releases". Compute is ephemeral; S3 is the source of truth.

Here: **MinIO** (single-node, lab sized). Buckets created: `datasets`,
`checkpoints`, `mlflow`, `models`.

```bash
./install.sh
kubectl -n mlops port-forward svc/minio-console 9001:9001   # UI
# in-cluster endpoint: http://minio.mlops.svc.cluster.local:9000
```

`install.sh` also copies the credentials Secret `minio-creds` into
`training`, `llm-serving` and `evaluation` so jobs can read/write.

> Licensing/distribution note: MinIO changed how it distributes community
> images in 2025. If the images are unavailable, swap in **SeaweedFS**,
> **Garage**, or **Ceph RGW** (all S3-compatible) — nothing else in this
> repo depends on MinIO specifically, only on the S3 API + `minio-creds`.
