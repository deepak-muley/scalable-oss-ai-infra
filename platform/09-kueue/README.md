# Kueue — GPU quota, queueing, fair sharing, preemption

The default kube-scheduler places pods; it does not decide *which job gets
the GPUs* when demand exceeds supply. Kueue adds that job-level layer:

* **ResourceFlavor** – a kind of hardware (e.g. `h100`, `rtx4090`) mapped to node labels.
* **ClusterQueue** – quota of flavors (e.g. 8 GPUs) + preemption policy.
* **Cohort** – ClusterQueues that can borrow each other's idle quota.
* **LocalQueue** – namespace-scoped handle that users submit to.
* **WorkloadPriorityClass** – lets interactive / prod jobs preempt batch.
* All-or-nothing admission (gang semantics) for multi-pod jobs via `waitForPodsReady` (see values.yaml).

Works with: batch Jobs, Kubeflow TrainJob/PyTorchJob, RayJob/RayCluster,
JobSet, LeaderWorkerSet, plain Deployments/Pods.

The sample `queues.yaml` splits the lab's GPUs into a **training** queue and
an **inference-batch** queue in one cohort so they can lend each other GPUs.
Edit the `nominalQuota` numbers to match your hardware.

Note: long-running online inference (vLLM Deployments) is usually NOT put
behind Kueue — give it reserved nodes or a higher priority instead.

## Worked example (kind or any cluster with ≥4 fake/real GPUs)

`training-cq` guarantees 4 GPUs and may borrow the 2 guaranteed to
`batch-inference-cq`. `kind/manifests/kueue-demo.yaml` submits three jobs
of 4 GPUs each (2 pods × 2 GPUs):

| Job | Priority | Result |
|---|---|---|
| `low-a` | low | Admitted. Uses the 4-GPU guarantee. |
| `low-b` | low | Pending. 4 are taken; borrowing adds at most 2, and 6 < 8. |
| `high-c` | high | Preempts `low-a` and takes the guarantee. `low-b` stays pending. |

```bash
kubectl apply -f kind/manifests/kueue-demo.yaml
kubectl get workloads -n training
kubectl describe workload -n training job-high-c-xxxxx   # name is prefixed
```

Apply the three Jobs separately if you want to watch each transition.
Change `nominalQuota` on `training-cq` from 4 to 8 and `low-b` admits
without borrowing. Set `reclaimWithinCohort` to `Never` and a lender stops
taking borrowed GPUs back. The longer write-up, and how this differs from
KAI placement, is [docs/22](../../docs/22-scheduling.md).

KAI (`platform/10-kai-scheduler`) is a second scheduler you opt into per
pod. Keep a given GPU in one quota system: Kueue nominal quotas and KAI
queue quotas must not both count the same devices.

Check which integrations your release enables (TrainJob / LWS support was
added in later 0.1x releases):

```bash
kubectl -n kueue-system get cm kueue-manager-config -o yaml | grep -A20 frameworks
```
