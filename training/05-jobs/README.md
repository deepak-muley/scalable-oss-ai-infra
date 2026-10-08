# Training job examples

| File | Engine | What it teaches |
|---|---|---|
| `trainjob-pytorch-ddp.yaml` | Kubeflow Trainer | multi-node DDP with torchrun, NCCL, Kueue queueing |
| `trainjob-lora-finetune.yaml` | Kubeflow Trainer | LoRA SFT of a small LLM → MLflow metrics → adapter to S3 → served by vLLM (inference/05-model-catalog/lora-multi-adapter.yaml) |
| `rayjob-train.yaml` | KubeRay | Ray Train TorchTrainer on an ephemeral Ray cluster |
| `rayjob-batch-inference.yaml` | KubeRay | Ray Data + vLLM offline batch inference (synthetic data / evals) |

All carry `kueue.x-k8s.io/queue-name: research`, so they wait in the
`training-cq` queue (platform/09-kueue) when GPUs are busy:

```bash
kubectl get workloads -n training        # Kueue's view: admitted / pending
kubectl get trainjobs,rayjobs -n training
```

## The end-to-end loop (train → track → register → serve → eval)

```
trainjob-lora-finetune ──metrics──▶ MLflow
        │ adapter
        ▼
  s3://checkpoints/adapters/lab-assistant (MinIO)
        │ initContainer sync
        ▼
  vllm-lora (model "lab-assistant") ──▶ AI gateway ──▶ evaluation/02-lm-eval
```
