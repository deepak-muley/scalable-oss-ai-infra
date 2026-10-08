# NVIDIA GPU Operator

Turns a plain node with an NVIDIA GPU into a schedulable `nvidia.com/gpu`
resource. It manages, as DaemonSets:

| Component | What it does |
|---|---|
| Node Feature Discovery (NFD) | labels nodes with PCI/CPU features |
| GPU Feature Discovery (GFD) | labels `nvidia.com/gpu.product`, `.memory`, `.count`, MIG caps |
| Driver container | installs the kernel driver (optional if host already has it) |
| Container Toolkit | configures containerd with the `nvidia` runtime + RuntimeClass |
| Device Plugin | advertises `nvidia.com/gpu` to kubelet (with time-slicing / MIG) |
| DCGM Exporter | GPU metrics (util, mem, power, temp, XID errors) for Prometheus |
| MIG Manager | repartitions A100/H100/H200/B200 into MIG slices from a node label |
| Validator | runs CUDA sample to prove the stack works |

## Install

```bash
# Host already has a driver (common on lab boxes)?  DRIVER_ENABLED=false
DRIVER_ENABLED=false ./install.sh
kubectl get pods -n gpu-operator          # wait for all Running/Completed
kubectl apply -f test-gpu-pod.yaml && kubectl logs -f gpu-smoke-test
```

## Sharing GPUs in a lab

| Mode | When | How |
|---|---|---|
| Whole GPU | real workloads, training | default |
| **Time-slicing** | many tiny models / notebooks on consumer GPUs; no memory isolation | `kubectl apply -f time-slicing-config.yaml` then patch (below) |
| **MIG** | A100/H100+: hard-isolated slices (e.g. 7× 1g.10gb) | label node `nvidia.com/mig.config=all-1g.10gb` |
| DRA (Dynamic Resource Allocation) | K8s ≥1.34, NVIDIA DRA driver — future of GPU requests | see docs/03 |

```bash
kubectl apply -f time-slicing-config.yaml
kubectl patch clusterpolicies.nvidia.com/cluster-policy -n gpu-operator --type merge \
  -p '{"spec":{"devicePlugin":{"config":{"name":"time-slicing-config","default":"any"}}}}'
```

```bash
# MIG example (A100 80GB / H100): 7 isolated 1g.10gb slices
kubectl label node <node> nvidia.com/mig.config=all-1g.10gb --overwrite
```
