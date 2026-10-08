# JupyterHub — the researcher workbench

Researchers live in notebooks. JupyterHub (Zero to JupyterHub chart) gives
each user a pod with persistent home storage, chosen from **profiles**:

| Profile | Image | Use |
|---|---|---|
| CPU small | `quay.io/jupyter/minimal-notebook` | data wrangling, calling models via the gateway, MLflow queries |
| 1 GPU, PyTorch | `quay.io/jupyter/pytorch-notebook` (CUDA tag) | debugging training code on a real GPU before submitting a TrainJob |
| Ray client | minimal notebook + `ray[client]` | drive the dev RayCluster (`training/04-kuberay/raycluster-dev.yaml`) from a notebook |

Every server gets `MLFLOW_TRACKING_URI` and `RAY_ADDRESS`
(`ray://ray-dev-head-svc.training.svc.cluster.local:10001`). Idle servers are
culled after 1h, which matters because **an idle GPU notebook is the most
expensive thing in a lab**.

```bash
./install.sh
kubectl -n workbench port-forward svc/proxy-public 8000:80   # http://localhost:8000
# lab auth: any username, password from values.yaml (DummyAuthenticator)
```

## Notes

* **Auth:** `DummyAuthenticator` is for a single-user lab only. Use
  `GenericOAuthenticator` against Keycloak (commented in values.yaml), so the
  same identity follows users to the gateway, MLflow and Grafana.
* **GPU notebooks bypass Kueue** by default. To make them queue against
  quota, enable Kueue's pod integration and label notebook pods with
  `kueue.x-k8s.io/queue-name`. That's a good exercise.
* **Ray client** requires the same Ray *and* Python minor version as the
  cluster (2.46 / py3.11 here). Install with `pip install "ray[client]==2.46.0"`.
* **Pod Security:** the `workbench` namespace is labelled PSA `baseline`.
  Notebooks run as uid 1000 and need no privileges.
* Alternatives: Kubeflow Notebooks, VS Code (code-server), Marimo.
