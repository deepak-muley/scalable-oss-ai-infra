# KubeRay — Ray clusters on Kubernetes (training, batch inference, RL, serving)

[KubeRay](https://github.com/ray-project/kuberay) runs [Ray](https://ray.io)
as Kubernetes-native resources:

| CRD | Use |
|---|---|
| `RayCluster` | long-lived cluster (head + autoscaled worker groups) — notebooks, interactive dev |
| `RayJob` | ephemeral cluster per job: create → run entrypoint → tear down. Kueue-aware. |
| `RayService` | Ray Serve app with zero-downtime upgrades (e.g. Ray Serve LLM, see inference/05-model-catalog/rayservice-llm.yaml) |

Why Ray in an LLM lab:
* **Ray Train** – distributed PyTorch/DeepSpeed/FSDP with fault tolerance.
* **Ray Data** – streaming data preprocessing & **offline batch inference**
  with vLLM over millions of prompts (synthetic data, evals, labelling).
* **RL / post-training** – frameworks like **veRL**, **OpenRLHF**, **NeMo-RL**,
  **SkyRL** use Ray to co-schedule trainer actors (FSDP/Megatron) with rollout
  actors (vLLM/SGLang) — the core loop of RLHF / RL-from-verifiable-rewards.
* **Ray Serve LLM** – Python-composable serving on the same substrate.

```bash
./install.sh
kubectl apply -f raycluster-dev.yaml          # interactive cluster
kubectl apply -f ../05-jobs/rayjob-train.yaml # Ray Train job (queued by Kueue)
kubectl -n training port-forward svc/ray-dev-head-svc 8265:8265   # Ray dashboard
```
