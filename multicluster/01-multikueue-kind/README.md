# MultiKueue on two kind clusters

Creates `ai-lab-manager` and `ai-lab-worker1` (default kindnet CNI to keep
it light; they're independent of the main `kind/` lab), installs Kueue on
both, gives the worker fake GPUs, wires MultiKueue, and runs a GPU Job that
is **submitted to the manager but runs on the worker**.

```bash
./up.sh
export KUBECONFIG=/tmp/ai-lab-multicluster.kubeconfig
kubectl --context kind-ai-lab-manager create -f demo-job.yaml   # generateName => create
kubectl --context kind-ai-lab-manager get workloads -n training    # admitted via multikueue-ac
kubectl --context kind-ai-lab-worker1 get pods -n training         # <- the pods are HERE
kubectl --context kind-ai-lab-manager get job -n training          # status synced back
./down.sh
```

Notes and version-dependent bits:

* MultiKueue APIs are `kueue.x-k8s.io/v1beta1` (`MultiKueueConfig`,
  `MultiKueueCluster`, `AdmissionCheck`). Feature maturity differs by Kueue
  release; this targets 0.13.x.
* For `batch/v1` Jobs the manager relies on `spec.managedBy` (Kubernetes
  ≥ 1.32 has the `JobManagedBy` gate on by default). Recent kind node images
  are new enough.
* The worker kubeconfig stored in the manager **must use the worker's
  address on the docker network**. That's why `up.sh` uses
  `kind get kubeconfig --internal` (`https://ai-lab-worker1-control-plane:6443`).
  A `127.0.0.1:<port>` address would point at the manager itself.
* For brevity the lab uses the worker's admin kubeconfig. In real fleets,
  create a dedicated ServiceAccount on each worker with only the RBAC
  MultiKueue needs (see the Kueue docs) and rotate its token.
* Namespaces and LocalQueues must exist with the **same names** on the
  manager and on every worker.
