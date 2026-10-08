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

Check which integrations your release enables (TrainJob / LWS support was
added in later 0.1x releases):

```bash
kubectl -n kueue-system get cm kueue-manager-config -o yaml | grep -A20 frameworks
```
