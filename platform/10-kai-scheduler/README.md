# KAI Scheduler — where a GPU pod lands

[KAI Scheduler](https://github.com/kai-scheduler/KAI-Scheduler) is a CNCF
sandbox Kubernetes scheduler, originally the Run:ai scheduler and now
maintained in the open. It is built for GPU clusters: hierarchical quotas,
fair share, preemption, gang scheduling, bin-pack versus spread, fractional
GPUs, and topology (rack, NVLink domain).

Read [docs/22](../../docs/22-scheduling.md) first if "scheduler" still means
three different things. Short version for this folder:

| Question | Component in this lab |
|---|---|
| May this **job** start, given the team's quota? | **Kueue** (`platform/09-kueue`) — the default for TrainJob, RayJob, JobSet, LWS |
| **Which node and which GPU** should this pod use? | **KAI**, for pods that opt in with `schedulerName: kai-scheduler` |
| Which **replica** should this HTTP request hit? | Envoy / the production-stack router / the Inference Extension — not this folder |

KAI runs **next to** kube-scheduler. Pods that omit `schedulerName` are
unchanged. The admission webhook matches that scheduler name, so a KAI
outage does not block pod creates for the rest of the cluster. Online vLLM
Deployments stay on kube-scheduler so a batch queue cannot evict a model
that is serving traffic.

Give each GPU to one system. If Kueue's nominal quotas and KAI's queue
quotas both count the same device, both will admit work that cannot fit.
The sample budgets below assume **4 GPUs belong to KAI**. Leave serving
GPUs out of `ai-lab-gpus`, and keep Kueue's `nominalQuota` on a different
slice (or at zero) while you are experimenting with KAI.

## Install

```bash
./platform/10-kai-scheduler/install.sh
# edit gpu quota/limit in queues.yaml to match the pool KAI is allowed to use
kubectl apply -f platform/10-kai-scheduler/queues.yaml
kubectl get queues.scheduling.run.ai
kubectl -n kai-scheduler get pods
```

The chart creates `default-parent-queue` and `default-queue` (no GPU
guarantee, unlimited limit). Lab examples use the leaves in `queues.yaml`.

`SKIP_KAI=true ./scripts/install-all.sh platform` skips this layer.

## The queue tree

```
ai-lab-gpus          quota 4, limit 4     the whole KAI pool
├── notebooks                 quota 1, limit 1,  priority 200   interactive
├── distributed-training      quota 2, limit 4,  priority 100   gang jobs; weight 2 on spare GPUs
└── offline-batch             quota 1, limit 4,  priority 50    soaks leftovers
```

Child quotas sum to 4, so each leaf has a guarantee. `limit: 4` on training
and batch lets them borrow GPUs a sibling is not using. `overQuotaWeight: 2`
on training means that, when two queues both want the spare, training gets
twice batch's share. `notebooks` has `limit: 1`, so interactive work cannot
grow past one GPU even when the pool is idle — that is the cap
`examples/04-preemption-low.yaml` relies on.

CPU and memory limits are `-1` (uncapped). A limit left at 0 means the queue
may not use that resource at all, which is a common reason a pod sits
Pending with an empty events list.

Only **leaves** take workloads. The label on the pod is the leaf name:

```yaml
metadata:
  labels:
    kai.scheduler/queue: distributed-training
spec:
  schedulerName: kai-scheduler
```

Submit into a workload namespace (`training`, `evaluation`), never into
`kai-scheduler`.

## Examples

Apply one at a time. Delete the previous pods first so the 4-GPU budget is
free (`kubectl delete -f examples/<file>.yaml`).

```bash
# 1. One whole GPU. On kind this is enough: fake GPUs count as nvidia.com/gpu.
kubectl apply -f platform/10-kai-scheduler/examples/01-whole-gpu-pod.yaml
kubectl get pod -n training kai-whole-gpu -o wide

# 2. Two pods, half a GPU each. Real GPU only — reservation pods call NVML.
kubectl apply -f platform/10-kai-scheduler/examples/02-fractional-gpu.yaml
kubectl get pods -n kai-resource-reservation          # the device holder
kubectl get pods -n training -o wide                  # both user pods, one node

# 3. Gang: 2 pods start together or not at all.
kubectl apply -f platform/10-kai-scheduler/examples/03-gang-job.yaml
kubectl get podgroups -n training
kubectl describe job -n training kai-gang             # events explain the wait

# 4. Priority. notebooks.limit is 1 GPU. Apply low, wait until Running, then high.
kubectl apply -f platform/10-kai-scheduler/examples/04-preemption-low.yaml
kubectl get pods -n training -l app=kai-preempt -w
kubectl apply -f platform/10-kai-scheduler/examples/04-preemption-high.yaml
# kai-train-low (priority class train, value 50) yields to kai-build-high
# (build, value 100, not preemptible).

# 5. Topology. Label racks first or the job stays Pending on purpose.
kubectl apply -f platform/10-kai-scheduler/examples/05-topology-job.yaml
```

KAI writes a Kubernetes Event for each scheduling decision. `kubectl describe`
on the pod, Job, or PodGroup is the trace. There is no separate status CLI.

### Bin-pack versus spread

`values.yaml` sets placement to **binpack** for GPU and CPU: fill the
current node before opening the next one. On two nodes of 4 GPUs, four
1-GPU pods occupy one node and leave the other empty, so a later 4-GPU gang
still fits.

**Spread** does the opposite (one pod per node, until every node has one).
A node failure hurts less, and the free GPUs are shattered: four 1-GPU pods
on four 2-GPU nodes leave no node with two free GPUs.

```bash
helm upgrade kai-scheduler oci://ghcr.io/kai-scheduler/kai-scheduler/kai-scheduler \
  -n kai-scheduler --version "$KAI_SCHEDULER_VERSION" \
  -f platform/10-kai-scheduler/values.yaml \
  -f platform/10-kai-scheduler/values-spread.yaml
```

Placement is a scheduler setting, not a per-pod annotation. Re-apply the
pods after the upgrade; already-running pods stay where they are until
something preempts or you delete them.

### Fractional GPU modes

| `global.gpuSharingMode` | What you get | When |
|---|---|---|
| `NonMemoryEnforced` | Scheduler packs fractions onto one device. The process can still allocate past its fraction. | This lab. No extra operator. |
| `HamiCore` | Same annotations, HAMi enforces the memory cap. | Untrusted notebooks sharing a GPU. See [`platform/11-hami`](../11-hami/README.md) |
| `NvFractions` | NVIDIA gpu-fractioning, CDI/NRI, per-container `nvidia.com/container.<name>.gpu-memory.request`. | Production isolation on recent GPU Operator. |
| `Disabled` | Fractional pods are rejected. | Whole GPUs only. |

Annotations that matter in this lab:

| Annotation | Meaning |
|---|---|
| `gpu-fraction: "0.5"` | Half of one GPU, by memory capacity. Must be `(0, 1)`. |
| `gpu-memory: "4096"` | 4096 MiB instead of a fraction. |
| `gpu-fraction-container-name` | Which container receives the fraction when the pod has a sidecar. Default is the first container. |
| `kai.scheduler/batch-min-member` | On a Job or JobSet: minimum pods that must fit together. Set it equal to `parallelism` for a real gang. |

A fractional pod must not also request `nvidia.com/gpu`.

### Gang, Ray, and TrainJob

KAI's podgrouper builds a PodGroup for Jobs, JobSets, and (with a recent
KubeRay) RayCluster / RayJob / RayService. You usually do not write a
PodGroup yourself. For Ray, the queue label goes on the cluster:

```yaml
apiVersion: ray.io/v1
kind: RayCluster
metadata:
  name: kai-ray
  namespace: training
  labels:
    kai.scheduler/queue: distributed-training
spec:
  headGroupSpec:
    template:
      spec:
        schedulerName: kai-scheduler
  # workerGroupSpecs: same schedulerName, and a GPU limit per worker
```

A Kubeflow TrainJob that should be placed by KAI needs the same label and
`schedulerName` on the pod template, and it should **not** also carry
`kueue.x-k8s.io/queue-name`. One admission controller per job.

### Topology

`examples/05-topology-job.yaml` defines a three-level topology (zone → rack
→ node). Required placement is a hard filter. Preferred placement packs the
gang into the tightest domain that still fits, so a 2-GPU job lands on one
rack when a rack has two GPUs and spills to a second rack only when it does
not.

For NVLink or an NVL72 domain, use the label the GPU Operator or DRA driver
actually sets, and put that label at the level where communication is
cheap. A tensor-parallel job wants that level as **required**. A
data-parallel job can leave it **preferred** and cross the network.

### Fair share, in one picture

Parent quota is 4. Training holds its 2, notebooks holds its 1, batch holds
its 1. Everyone is in quota; nobody is preempted.

Batch is idle. Training submits a 4-GPU gang. It already owns 2 and the
batch guarantee of 1 is free, and notebooks keeps its 1 because that queue
is higher priority and in quota. Training's limit is 4, so the gang fits
only if notebooks is also idle. If notebooks is busy, the gang waits (or
you raise nothing — the notebook cap is intentional).

Both training and batch are over quota and a new GPU appears. Training's
`overQuotaWeight` is 2 and batch's is 1, so training is offered two thirds
of the spare.

Queue **priority** (the integer on the Queue) orders queues. Pod
**priorityClassName** orders workloads inside a queue, and values ≥ 100 are
not preemptible. Those are different knobs. `train` / `build` /
`inference` are the classes the chart installs.

## kind

`kind/fake-gpus.sh` makes `nvidia.com/gpu` allocatable, which is enough for
examples 01, 03, and 04. Example 02 stays Pending: fractional mode starts a
reservation pod that needs NVML. Example 05 needs the node labels in its
header; the two gpu-sim workers can be one zone and two racks.

```bash
cd kind && ./up.sh
./platform/10-kai-scheduler/install.sh
kubectl apply -f platform/10-kai-scheduler/queues.yaml
kubectl apply -f platform/10-kai-scheduler/examples/03-gang-job.yaml
```

## Operate

```bash
kubectl get queues.scheduling.run.ai
kubectl describe queue distributed-training
kubectl get podgroups -A
kubectl -n kai-scheduler logs deploy/kai-scheduler-scheduler --tail=50
```

Pending and the queue exists: `kubectl describe pod` and look for a fit
error (fraction plus whole GPU, limit 0 on cpu/memory, topology label
missing, gang min-member larger than free GPUs). Pending and the queue does
not exist: the label points at a parent, or at a name you have not applied.

Upgrade with the same `install.sh` after bumping `KAI_SCHEDULER_VERSION` in
`versions.env` and the `targetRevision` in
`gitops/02-app-of-apps/apps/18b-kai-scheduler.yaml`. Read the project's
breaking-changes notes between minors; the queue API group is still
`scheduling.run.ai/v2`.
