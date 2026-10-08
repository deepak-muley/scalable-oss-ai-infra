# Kubeflow Trainer (v2) — distributed PyTorch / LLM fine-tuning jobs

Kubeflow Trainer v2 splits concerns:

* **`ClusterTrainingRuntime` / `TrainingRuntime`** – written by the platform
  team: the blueprint (image, torchrun/MPI launcher, JobSet topology,
  defaults). Shipped runtimes include `torch-distributed`, `deepspeed-distributed`,
  `mlx-distributed`, and LLM fine-tuning blueprints (`torchtune-*`).
* **`TrainJob`** – written by researchers: "run this command on N nodes
  with M GPUs each using runtime X". Internally becomes a **JobSet**.
* Injects `PET_NNODES`, `PET_NPROC_PER_NODE`, `PET_NODE_RANK`,
  `PET_MASTER_ADDR/PORT` so `torchrun` just works.
* Python SDK (`kubeflow-trainer` / `kubeflow` package) to submit from notebooks.

(The older Training Operator v1 `PyTorchJob` still exists and is widely
documented; v2 is the path forward.)

```bash
./install.sh
kubectl get clustertrainingruntimes
kubectl apply -f ../05-jobs/trainjob-pytorch-ddp.yaml
```
