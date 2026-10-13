# LeaderWorkerSet (LWS) — multi-node model replicas

[LeaderWorkerSet](https://lws.sigs.k8s.io/) is a Kubernetes SIG Apps API for
**multi-node, multi-pod replicas**. One "replica" is one leader pod plus N
worker pods that are created, scheduled, restarted, and scaled *as a unit*.

That is how you serve a model that does not fit on one node (for example
DeepSeek-V3/R1 or Llama-405B): tensor-parallel within a node, pipeline- or
expert-parallel across nodes. Used by vLLM multi-node, llm-d, KServe, NVIDIA
Dynamo, and SGLang deployments.

The working example in this lab is
[`inference/05-model-catalog/llm-multinode-lws.yaml`](../../inference/05-model-catalog/llm-multinode-lws.yaml).

## What a replica is

A Deployment replica is one pod. An LWS replica is a **group**:

| Pod | Name pattern | Role in the catalog example |
|---|---|---|
| Leader | `<name>-0` | Ray head, then the vLLM HTTP server on port 8000 |
| Worker | `<name>-0-1`, … | Ray worker; GPUs only, no HTTP server |

With `replicas: 1` and `size: 2`, you get one pair. A second replica
(`replicas: 2`) is another independent pair (`…-1` and `…-1-1`). Scaling
adds or removes whole groups. Clients talk only to leaders (the Service
selects `role: leader`).

The controller injects three environment variables into every container:

| Variable | Meaning |
|---|---|
| `LWS_LEADER_ADDRESS` | Stable DNS name of this group's leader (headless Service) |
| `LWS_GROUP_SIZE` | Pods in the group |
| `LWS_WORKER_INDEX` | `0` on the leader, `1`, `2`, … on workers |

## Why use it

Multi-node inference is one process group spread across machines. In the
catalog example, vLLM starts a Ray cluster inside the group, then shards the
model:

* **Tensor parallel 8** stays inside one node (NVLink).
* **Pipeline parallel 2** crosses the two nodes.

`8 × 2 = 16` GPUs → each pod requests `nvidia.com/gpu: "8"` and `size` is
`2`. That matches the sizing for Llama-3.1-405B-Instruct-FP8 in
[docs/07](../../docs/07-model-catalog.md) (~410 GB FP8 weights on
2 nodes × 8×80 GB). DeepSeek-V3/R1 uses the same idea with expert
parallelism (llm-d `wide-ep-lws` guide).

A Deployment cannot express that unit: pods would scale, restart, and roll
one at a time, and workers would have no stable leader address. If one rank
dies, the NCCL/Ray collective is already dead; bringing only that pod back
does not rejoin it. LWS's default restart policy,
`RecreateGroupOnPodRestart`, deletes and recreates the whole group so every
rank starts together. Chaos experiment
[`04-kill-lws-worker.yaml`](../../reliability/02-experiments/04-kill-lws-worker.yaml)
expects exactly that: kill one worker and the model is down for a full
weight reload.

| Primitive | Role in this lab |
|---|---|
| **LeaderWorkerSet** | Long-running *serving* group (this folder) |
| **JobSet** | Finishing *training* jobs (Kubeflow Trainer) |
| **RayCluster** | Ray-specific control plane (KubeRay) |

This catalog still uses Ray *inside* the containers as vLLM's multi-node
bootstrap; Kubernetes owns the group via LWS.

## When to use it

| Situation | Use |
|---|---|
| Model needs more than one node (TP on-node × PP/EP across nodes) | **LWS** |
| Model fits on one node (e.g. 70B TP on 4×80 GB) | Deployment — `llm-tensor-parallel.yaml` |
| Batch training that finishes | JobSet / TrainJob, not LWS |

Fast inter-node networking (InfiniBand or RoCE) matters: pipeline and
expert traffic across nodes is much slower on a plain pod network. See
[docs/03](../../docs/03-hardware-and-cluster-prereqs.md) and Lab 3.1–3.3 in
[docs/09](../../docs/09-learning-path.md).

## Install

Pinned in `versions.env` as `LWS_VERSION` (currently `0.7.0`). There is no
`values.yaml` in this folder; the chart is installed as published.

```bash
./platform/08-lws/install.sh
kubectl -n lws-system get pods
kubectl get crd leaderworkersets.leaderworkerset.x-k8s.io
```

The same step runs from `scripts/install-all.sh`, `kind/up.sh`, and the
Argo CD app [`gitops/02-app-of-apps/apps/17-lws.yaml`](../../gitops/02-app-of-apps/apps/17-lws.yaml).
Install order is in [docs/04](../../docs/04-install-runbook.md) (after KEDA,
before Kueue). Kueue can admit LWS workloads; see
[`platform/09-kueue`](../09-kueue/README.md).

## Deploy the catalog example

Prerequisites: GPU Operator, `model-cache` PVC, `hf-token` Secret, and
enough GPUs (2 nodes × 8 GPUs for the default 405B FP8 shape).

```bash
kubectl apply -f inference/05-model-catalog/llm-multinode-lws.yaml
kubectl get lws -n llm-serving
kubectl get pods -n llm-serving -l leaderworkerset.sigs.k8s.io/name=vllm-llama405b
```

The leader waits until Ray sees `LWS_GROUP_SIZE` members, then starts vLLM.
Workers join `LWS_LEADER_ADDRESS`. Add a matching rule in
`gateway/03-ai-routes/ai-gateway-route.yaml` pointing at Service
`vllm-llama405b` in `llm-serving`.

To run two independent copies, set `spec.replicas: 2` (32 GPUs). An HPA can
scale `.spec.replicas`; it watches **leader** pod metrics, so the leader
should expose a metric that represents the whole group.

## Configure a LeaderWorkerSet

API: `leaderworkerset.x-k8s.io/v1`. Fields below match the 0.7.0 chart this
lab installs. Upstream reference:
[LeaderWorkerSet API](https://lws.sigs.k8s.io/docs/reference/leaderworkerset.v1/).

### Spec fields that matter here

| Field | Meaning |
|---|---|
| `spec.replicas` | Number of groups. Default `1`. Scale-down deletes that group's leader and worker StatefulSet. |
| `leaderWorkerTemplate.size` | Pods per group, leader included. Minimum `1`. Equals nodes per model copy when each pod takes a whole node. |
| `leaderTemplate` / `workerTemplate` | Ordinary pod specs. Leader runs HTTP + readiness; workers join the collective and share the model cache / `/dev/shm`. |
| `restartPolicy` | See below. |
| `spec.startupPolicy` | See below. |
| `spec.networkConfig.subdomainPolicy` | `Shared` (default) or `UniquePerReplica` headless Services. |
| `spec.rolloutStrategy` | Only `RollingUpdate`. Defaults: `maxUnavailable: 1`, `maxSurge: 0` (one group at a time, no surge). `partition` holds lower ordinals on the old template (canary). |
| `subGroupPolicy` | Split one group into smaller pod subgroups (advanced; catalog example omits it). |

### `restartPolicy`

| Value | Behavior |
|---|---|
| `RecreateGroupOnPodRestart` | Default in 0.7.0. Any pod recreate or container restart recreates the **group**. What Ray/NCCL serving needs; what the catalog sets. |
| `None` | Only the failed pod restarts (old name was `Default`). Other ranks stay up → broken collective. |

### `startupPolicy`

| Value | Behavior |
|---|---|
| `LeaderCreated` | Default. Workers are created as soon as the leader Pod object exists. Keep this for the vLLM example: the leader does not open port 8000 until workers have joined Ray. |
| `LeaderReady` | Workers wait until the leader is Ready. Use when workers must attach to a coordinator that is already serving. On the catalog vLLM manifest this **deadlocks** (Ready = port 8000, which opens only after workers join). |

### Placement and topology

Annotation `leaderworkerset.sigs.k8s.io/exclusive-topology: kubernetes.io/hostname`
puts each pod of a group on a different node and keeps other groups off
those nodes. The catalog omits it because each pod already requests a full
node's GPUs. Add it if a pod requests only part of a node. For
quota-gated, all-or-nothing placement with binpacking, prefer
[Kueue topology-aware scheduling](https://lws.sigs.k8s.io/docs/examples/leaderworkerset/topology-aware-scheduling/)
instead of the exclusive-topology annotation alone.

### Keep vLLM flags aligned with the group

`tensor-parallel-size` × `pipeline-parallel-size` must equal
(GPUs per pod) × `size`. Change the node count and you change `size`, the
GPU request, and `--pipeline-parallel-size` together.

## Failure mode to plan for

`RecreateGroupOnPodRestart` means a single worker death takes the whole
copy down for a full model load. Mitigations used in this lab:

* `spec.replicas` ≥ 2 when you have the GPUs
* Gateway fallback route to a smaller single-node model
* Measure downtime with Lab 3.3 and chaos experiment 4

## Related

* [docs/02](../../docs/02-oss-components.md) — component catalog row
* [docs/07](../../docs/07-model-catalog.md) — GPU sizing for 405B / DeepSeek
* [docs/19](../../docs/19-advanced-serving.md) — wide EP over LWS
* [inference/07-llm-d](../../inference/07-llm-d/README.md) — `wide-ep-lws` guide
* Upstream: [lws.sigs.k8s.io](https://lws.sigs.k8s.io/)
