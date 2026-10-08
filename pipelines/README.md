# Pipelines — turning one-off jobs into a repeatable model factory

Individual jobs (`training/05-jobs`, `evaluation/`) teach the pieces. A lab
ships models through a **pipeline**: the same DAG every time, with
parameters, retries, artifacts, an audit trail and an automated quality gate.

```
data-prep (RayJob) ─► train (TrainJob) ─► register (MLflow) ─► deploy candidate (vLLM)
                                                                    │
                          promote (gateway alias) ◄── score ≥ T ── eval (lm-eval)
                          reject + clean up      ◄── score <  T ──┘
```

## Which orchestrator?

| | **Argo Workflows** (used here) | **Kubeflow Pipelines** | **Ray (Workflows / plain Ray tasks)** |
|---|---|---|---|
| Model | K8s-native CRD; each step is a pod or a K8s resource | Python DSL (`kfp`) compiled to IR, runs on Argo-like backend | Python functions/actors inside one Ray cluster |
| Strength | creates *any* K8s object as a step (RayJob, TrainJob, Deployment) and waits on its status; CronWorkflows; huge ecosystem (Argo Events, CD) | ML-native UX: typed artifacts, lineage, caching of steps, experiment UI | low-latency fine-grained steps, data stays in Ray object store |
| Weakness | YAML-heavy; ML lineage is DIY (we use MLflow) | heavier install; KFP v2 is opinionated about components | not a cross-system orchestrator; Ray Workflows is in maintenance |
| Use it for | **platform-level release pipelines** spanning many systems | data-scientist-authored pipelines with lineage and caching | the *inside* of a step (data processing, RL loops) |

Common real-world split: Argo Workflows (or Airflow/Flyte/Dagster) orchestrates
the release, Ray does the heavy lifting inside steps, and MLflow records lineage.

| Folder | |
|---|---|
| [`01-argo-workflows`](01-argo-workflows/) | install + RBAC for pipelines that drive TrainJobs, RayJobs, Deployments and gateway routes |
| [`02-model-release-pipeline`](02-model-release-pipeline/) | `model-release` WorkflowTemplate + nightly regression CronWorkflow |

Narrative and exercises: [docs/15-gitops-and-pipelines.md](../docs/15-gitops-and-pipelines.md).
