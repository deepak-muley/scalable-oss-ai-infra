# Storage — shared model cache & checkpoints

LLM serving and training are storage-heavy:

| Data | Size | Access pattern | Storage here |
|---|---|---|---|
| Model weights (HF cache) | 1 GB – 800 GB | read-many by every replica | **RWX NFS** (`nfs-client` class) |
| Training checkpoints | 10s–100s GB | write by trainer, read by eval/serving | RWX NFS or MinIO (S3) |
| Datasets | any | streamed by trainers | MinIO (S3) |
| Prometheus / MLflow DB | small | RWO | `local-path` or NFS |

Why RWX for weights: with a shared volume, a new vLLM replica starts in
seconds-to-minutes (page-cache warm, no re-download from Hugging Face).
That is what makes autoscaling practical.

## Options

1. **NFS subdir provisioner** (default here) – point it at any NFS export
   (a NAS, or `apt install nfs-kernel-server` on a storage box).
2. **local-path-provisioner** – zero-dependency RWO, fine for single node.
3. Production-grade alternatives: Longhorn, Rook-Ceph (CephFS = RWX),
   JuiceFS, or a parallel FS (Weka, Lustre) for big training clusters.

```bash
NFS_SERVER=192.168.1.10 NFS_PATH=/export/k8s ./install.sh
kubectl get sc       # expect: nfs-client (default)
```

Tip: on GPU nodes, also make sure there is a fast **local NVMe** for
`/var/lib/containerd` — vLLM/PyTorch images are 8–20 GB.
