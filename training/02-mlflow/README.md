# MLflow — experiment tracking & model registry

Every training/eval job logs params, metrics and artifacts here, so runs are
comparable and reproducible. Artifacts go to MinIO bucket `mlflow`.

```bash
./install.sh
kubectl -n mlops port-forward svc/mlflow 5000:80
# in-cluster: MLFLOW_TRACKING_URI=http://mlflow.mlops.svc.cluster.local
```

Alternatives: Weights & Biases (SaaS / self-hosted), Aim, ClearML.

> Chart keys differ across MLflow charts; `helm show values community-charts/mlflow`
> is authoritative. For production use a Postgres backend store instead of SQLite.
