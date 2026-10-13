# HAMi — share a GPU by memory and compute

[HAMi](https://project-hami.io/) (Heterogeneous AI Computing Virtualization
Middleware, CNCF sandbox, formerly k8s-vGPU-scheduler) lets several pods
share one accelerator and asks each pod for a memory size and a compute
share. The same scheduler covers NVIDIA, AMD Instinct, and a few other
vendors, each with its own device plugin and its own in-container limiter.

This folder is a design note. `scripts/install-all.sh` does not install
HAMi. The lab uses a whole `nvidia.com/gpu` from the
[GPU Operator](../05-gpu-operator/README.md). Read this when you want a
hard memory cap on a shared NVIDIA card, or when an AMD node joins the
cluster.

Re-check the HAMi docs before you install. The AMD device plugin in
particular is young (chart `0.0.1` at the time of writing).

## How a shared GPU is allocated

HAMi adds four pieces beside the vendor driver stack:

| Piece | Runs as | Role |
|---|---|---|
| Mutating webhook | inside the `hami-scheduler` pod | sees a pod that requests HAMi resources and sets `schedulerName: hami-scheduler`. A pod that already sets `schedulerName` is left alone |
| Scheduler extender | same pod | filters and scores nodes by remaining VRAM and compute, then writes the chosen device into pod annotations. Node and card placement are each `binpack` or `spread` |
| Device plugin | DaemonSet, one per vendor | registers the extended resources with the kubelet and, at `Allocate`, mounts the limiter library into the container |
| In-container limiter | library on the node, mounted into the pod | stops the process from allocating past its memory quota or using more than its compute share |

```
pod create
  → webhook sets schedulerName: hami-scheduler
  → scheduler picks a node and a device with enough free memory and compute
  → annotations record the device id, memory, and compute
  → device plugin Allocate() mounts the limiter and injects env vars
  → the process sees a smaller GPU
```

The webhook's failure policy is Ignore. If `hami-scheduler` is down, the
pod is admitted with the default scheduler and then sits Pending, because
the extended resources are not ordinary extended resources the default
scheduler can pack. Wait until `hami-scheduler` is Ready before submitting
GPU pods, and confirm the pod's `schedulerName`.

## NVIDIA, next to this lab's GPU Operator

Keep the GPU Operator for the driver, the container toolkit, GFD labels,
DCGM, and MIG Manager. One device plugin owns `nvidia.com/gpu`. HAMi's
plugin is that owner, so the operator's plugin stays off:

```yaml
# platform/05-gpu-operator/values.yaml
devicePlugin:
  enabled: false
```

Then install HAMi and point its device plugin at the RuntimeClass the
toolkit created:

```bash
helm repo add hami-charts https://project-hami.github.io/HAMi/
helm upgrade --install hami hami-charts/hami \
  --namespace kube-system --create-namespace \
  --set devicePlugin.runtimeClassName=nvidia
kubectl -n kube-system rollout status deploy/hami-scheduler
```

`runtimeClassName=nvidia` matters once the GPU Operator is 25.10 or newer:
that line makes `runc` the default runtime and uses CDI for ordinary device
plugins, while HAMi's default mode still passes the GPU UUID through
`NVIDIA_VISIBLE_DEVICES`. This lab pins GPU Operator v25.3.2, where the
`nvidia` runtime is already how containers see the GPU. Set the value
anyway so an operator upgrade does not silently stop HAMi from attaching
devices.

A pod asks for one physical GPU, a memory cap in MiB, and an optional
compute percentage (1–100):

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hami-nvidia-slice
spec:
  restartPolicy: Never
  containers:
    - name: cuda
      image: nvcr.io/nvidia/cuda:12.4.1-base-ubuntu22.04
      command: ["nvidia-smi"]
      resources:
        limits:
          nvidia.com/gpu: 1
          nvidia.com/gpumem: 4096
          nvidia.com/gpucores: 30
```

On the node, `nvidia.com/gpu` allocatable becomes the number of virtual
slots (physical cards times the chart's device split), not the number of
cards. In the pod spec, `nvidia.com/gpu: 1` still means one physical card.
Read real device memory from the node annotation HAMi writes
(`hami.io/node-nvidia-register`) when the allocatable number looks too big.
The limiter for NVIDIA is `libvgpu.so`, which intercepts CUDA allocations.

Kueue in this lab counts `nvidia.com/gpu` as whole cards
(`platform/09-kueue/queues.yaml`). A HAMi cluster advertises many virtual
slots under that same name, so a quota of `4` would mean four slots, not
four cards. Give HAMi its own ResourceFlavor and quota, or keep Kueue on
nodes that are still whole-GPU.

KAI is the other scheduler that can touch a GPU in this lab. Its
`HamiCore` sharing mode uses HAMi's limiter and KAI's own
`schedulerName: kai-scheduler`. The HAMi webhook will not override a
scheduler name that is already set, so a KAI pod stays with KAI. Use
`HamiCore` when KAI should place the pod and HAMi should only enforce the
cap. Use `hami-scheduler` when HAMi should do both. A pod should be in one
of those two arrangements.

## AMD, when an Instinct node joins

An AMD node needs a ROCm driver stack, then HAMi's AMD plugin. The CUDA
images in this repo (`vllm/vllm-openai`, the CUDA smoke-test pod) run on
NVIDIA. An AMD node runs a ROCm image (a `rocm/pytorch` tag, or a vLLM
build published for ROCm). The gateway can route to whichever backend is
actually serving the model; the device resource on the pod is what changes.

| | NVIDIA (this lab today) | AMD (HAMi soft vGPU) |
|---|---|---|
| Driver stack | NVIDIA GPU Operator, device plugin off | AMD GPU Operator, its device plugin off |
| HAMi plugin | the NVIDIA plugin in the HAMi chart | [`Project-HAMi/amd-device-plugin`](https://github.com/Project-HAMi/amd-device-plugin) |
| Count | `nvidia.com/gpu` | `amd.com/gpu` |
| Memory | `nvidia.com/gpumem` (MiB) | `amd.com/gpumem` (MiB) |
| Compute | `nvidia.com/gpucores` (percent of SMs) | `amd.com/gpucores` (percent of CUs, 1–100) |
| Limiter | `libvgpu.so` via CUDA intercept | `libamvgpu.so` via glibc `LD_AUDIT` |

Host check before any of the Kubernetes pieces: `amd-smi static --gpu 0`
prints the model, VRAM, and `NUM_COMPUTE_UNITS`. HAMi's AMD path was
validated upstream with ROCm 7.0.2.

Install order:

1. AMD GPU Operator for the driver and the ROCm userspace. Turn its device
   plugin off so it does not also register `amd.com/gpu`:

   ```bash
   kubectl -n kube-amd-gpu patch deviceconfig default --type=merge -p \
     '{"spec":{"devicePlugin":{"enableDevicePlugin":false}}}'
   ```

2. HAMi's scheduler, with the AMD resources in its device list:

   ```yaml
   devices:
     amd:
       customresources:
         - amd.com/gpu
         - amd.com/gpumem
         - amd.com/gpucores
   ```

3. The AMD device plugin. Upstream's current chart is `0.0.1`
   (`ghcr.io/project-hami/amd-device-plugin:0.0.1`). It discovers VRAM and
   CU count through amd-smi and libdrm, and it copies `libamvgpu.so` onto
   the node from a `postStart` hook. Do not also run the upstream ROCm
   `k8s-device-plugin` image; that plugin has no HAMi limiter.

   ```bash
   helm upgrade --install amd-gpu \
     https://github.com/Project-HAMi/amd-device-plugin/releases/download/amd-gpu-helm-0.0.1/amd-gpu-0.0.1.tgz \
     --namespace kube-system
   kubectl -n kube-system rollout status ds/amd-gpu-device-plugin-daemonset
   kubectl get node <amd-node> -o jsonpath='{.metadata.annotations.hami\.io/node-amd-register}'
   ```

   The annotation lists each card with `devmem` (MiB) and `devcore` (CU
   count). A node that is "unregistered" is a plugin that has not written
   this annotation yet.

A pod requests a slice and names the HAMi scheduler. `gpucores: 25` on a
304-CU MI300X is about 76 CUs. Omitting `amd.com/gpucores` gives the
container every CU on that card and still applies the memory cap.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: amd-vgpu-example
spec:
  schedulerName: hami-scheduler
  restartPolicy: Never
  containers:
    - name: pytorch
      image: rocm/pytorch:latest
      command: ["bash", "-c"]
      args:
        - |
          env | grep -E 'LD_AUDIT|HIP_DEVICE_MEMORY_LIMIT'
          python3 -c 'import torch; print(torch.cuda.mem_get_info(0)); print(torch.cuda.get_device_name(0))'
      resources:
        limits:
          amd.com/gpu: 1
          amd.com/gpumem: 49152
          amd.com/gpucores: 25
```

`HIP_DEVICE_MEMORY_LIMIT=49152m` and `LD_AUDIT` pointing at `libamvgpu.so`
mean the cap is installed. The plugin also sets `ROCR_VISIBLE_DEVICES` and
`HSA_CU_MASK` so the process sees only its CU range. The memory hook needs
glibc symbols through `GLIBC_2.34`. Ubuntu 20.04, RHEL 8, and Alpine (musl)
images fail to load it. Use a current `rocm/pytorch` tag or another glibc
image new enough for that symbol.

Two of those pods on one card are the sharing test: each sees about 48 GiB,
and a third that does not fit stays Pending with `CardInsufficientMemory`
rather than starting and faulting on the device.

`amd.com/gpu` is a different resource from `nvidia.com/gpu`. A Kueue
ClusterQueue that only lists `nvidia.com/gpu` will not admit an AMD pod.
Add a flavor whose node label selects the AMD nodes and whose covered
resource is `amd.com/gpu`, with a quota counted in AMD cards (or in HAMi
slots, once you have decided which number the queue tracks). kind's
`fake-gpus.sh` only patches `nvidia.com/gpu`, so an AMD schedule cannot be
rehearsed on the laptop cluster.

## When something is wrong

| What you see | What it usually means |
|---|---|
| Pod Pending, event from `default-scheduler`, `Insufficient nvidia.com/gpu` or `Insufficient amd.com/gpu` | the webhook did not run; `hami-scheduler` was not Ready. Delete the pod and retry |
| NVIDIA container has no GPU | GPU Operator device plugin is still running, or (operator ≥ 25.10) the pod is not on RuntimeClass `nvidia` |
| `hami.io/node-amd-register` missing `devmem` | `amd-device-plugin` is not healthy, or the AMD operator plugin is still registering `amd.com/gpu` |
| AMD pod shows the full card's memory inside the process | `LD_AUDIT` / `HIP_DEVICE_MEMORY_LIMIT` absent, or the image is older than glibc 2.34 |
| Kueue admits far more GPU work than you have cards | the queue is counting HAMi virtual slots as whole GPUs |
