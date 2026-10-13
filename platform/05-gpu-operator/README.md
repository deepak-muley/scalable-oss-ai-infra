# NVIDIA GPU Operator

The [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/index.html)
turns a node that has an NVIDIA GPU into a node where pods can request
`nvidia.com/gpu`. This lab pins chart **v25.3.2** (`GPU_OPERATOR_VERSION`
in `versions.env`). Helm installs one `ClusterPolicy`; the operator
reconciles that policy into DaemonSets on every GPU node.

A pod never talks to the operator. It asks Kubernetes for
`nvidia.com/gpu: 1`. The device plugin and the container toolkit are what
make that request land on a real device.

## What runs on a GPU node

| Component | DaemonSet / controller | What it does |
|---|---|---|
| Node Feature Discovery | `gpu-operator` NFD worker | labels the node with PCI and CPU features so the operator can find NVIDIA devices |
| Driver | `nvidia-driver-daemonset` | installs the kernel module. Off in this lab when the host already has a driver |
| Container Toolkit | `nvidia-container-toolkit-daemonset` | writes the `nvidia` runtime into containerd and creates RuntimeClass `nvidia` |
| Device plugin | `nvidia-device-plugin-daemonset` | registers `nvidia.com/gpu` (or MIG resource names) with the kubelet |
| GPU Feature Discovery | `gpu-feature-discovery` | labels `nvidia.com/gpu.product`, `.memory`, `.count`, MIG capability |
| DCGM exporter | `nvidia-dcgm-exporter` | utilization, memory, power, temperature, XID errors for Prometheus |
| MIG Manager | `nvidia-mig-manager` | applies a MIG geometry when you label the node; idle on GPUs that have no MIG |
| Validator | `nvidia-operator-validator` | runs a short CUDA check and reports the stack as ready |
| Operator | `gpu-operator` Deployment | watches `ClusterPolicy` and the node labels, and rolls the DaemonSets |

NFD and GFD are why Kueue flavors work. `platform/09-kueue/queues.yaml`
selects `nvidia.com/gpu.present: "true"`. A tighter flavor uses the product
label GFD writes, for example `nvidia.com/gpu.product: NVIDIA-H100-80GB-HBM3`.

## How a pod gets a GPU

1. The operator (or the host driver, in this lab) has loaded the kernel
   module. `nvidia-smi` works on the node.
2. The toolkit has configured containerd. A container that uses RuntimeClass
   `nvidia` can see the driver libraries and the device nodes.
3. The device plugin has told the kubelet "this node has N allocatable
   `nvidia.com/gpu`". `kubectl describe node` shows them under Allocatable.
4. A pod is admitted with `limits: nvidia.com/gpu: 1`. kube-scheduler places
   it on a node that still has one free. Kueue may have held the pod back
   before this, and KAI may place it when `schedulerName` is `kai-scheduler`.
   Neither of those is the GPU Operator.
5. The kubelet calls the device plugin `Allocate`. The plugin returns the
   device nodes and a CDI/env specification. containerd starts the container
   with those devices mounted. `nvidia-smi` inside the pod lists the card.

Whole-GPU mode, the default here, gives the container the entire device.
Time-slicing and MIG change what "1" means. They are configured below.

## Install

```bash
# Host already has a datacenter driver (the usual lab box):
DRIVER_ENABLED=false ./platform/05-gpu-operator/install.sh

# No host driver: the operator builds and loads the kernel module.
DRIVER_ENABLED=true ./platform/05-gpu-operator/install.sh

kubectl get pods -n gpu-operator          # Running, or Completed for the validator
kubectl get nodes -L nvidia.com/gpu.product,nvidia.com/gpu.count,nvidia.com/gpu.memory
kubectl apply -f platform/05-gpu-operator/test-gpu-pod.yaml
kubectl logs gpu-smoke-test               # nvidia-smi table and topology
```

`install.sh` passes `driver.enabled` from `DRIVER_ENABLED` and then applies
`values.yaml`. Pick one owner for the driver. A host driver plus
`driver.enabled=true` makes the driver DaemonSet fight the host module
(the usual crash loop in [docs/13](../../docs/13-troubleshooting.md)).

On v25.3 the operator also creates an `NVIDIADriver` custom resource from
the `driver` values. `kernelModuleType` is `auto`, `proprietary`, or `open`.
`auto` picks from the GPU and the driver branch. The old
`useOpenKernelModules` field is ignored from v25.3 onward. One
`NVIDIADriver` with no node selector covers every GPU node. Add another,
with a node selector and its own `version`, when nodes run different OS
versions or need different driver branches.

## Configure

Everything the lab changes lives in `values.yaml` or in a node label. After
editing values, re-run `install.sh` (it is `helm upgrade --install`). A
one-off experiment can patch the `ClusterPolicy` instead; the next Helm
upgrade overwrites that patch, so put anything you want to keep into
`values.yaml`.

### Driver, toolkit, metrics

| `values.yaml` key | This lab | Change it when |
|---|---|---|
| `driver.enabled` | `false`, overridden by `DRIVER_ENABLED` | the node image has no NVIDIA driver |
| `toolkit.enabled` | `true` | leave on unless the node image already configures the `nvidia` runtime |
| `devicePlugin.enabled` | `true` | set `false` only when [HAMi](../11-hami/README.md) owns `nvidia.com/gpu` |
| `gfd.enabled` | `true` | you want product / memory labels for Kueue flavors and node selectors |
| `nfd.enabled` | `true` | NFD is already installed cluster-wide; a second copy fights over the same labels |
| `dcgmExporter.enabled` | `true` | you want GPU metrics |
| `dcgmExporter.serviceMonitor.enabled` | `true` | kube-prometheus-stack (`platform/06-monitoring`) should scrape it. Install monitoring after the operator so the CRD exists |
| `mig.strategy` | `single` | see MIG below |
| `migManager.enabled` | `true` | the manager stays idle until a node is labeled; safe to leave on |
| `driver.rdma.enabled` | commented out | InfiniBand or RoCE with the NVIDIA Network Operator, for GPUDirect. See [docs/03](../../docs/03-hardware-and-cluster-prereqs.md) |

DCGM series and the dashboards that use them are in
[docs/08](../../docs/08-observability.md).

### Whole GPU

The default. A container with `nvidia.com/gpu: 1` is the only container on
that device. Serving and training in this lab use this. Allocatable equals
the number of physical GPUs GFD reports.

### Time-slicing

`time-slicing-config.yaml` advertises each physical GPU as **4**
`nvidia.com/gpu`. CUDA contexts take turns on the SMs. Memory is still one
shared pool: one pod can allocate the whole framebuffer and OOM its
neighbors. Cap each server with `--gpu-memory-utilization` so the
co-tenants fit (four pods at `0.2` is the example in that file).

```bash
kubectl apply -f platform/05-gpu-operator/time-slicing-config.yaml
kubectl patch clusterpolicies.nvidia.com/cluster-policy -n gpu-operator --type merge \
  -p '{"spec":{"devicePlugin":{"config":{"name":"time-slicing-config","default":"any"}}}}'
```

`default: any` applies the ConfigMap key `any` on every GPU node. To slice
only some nodes, omit `default` and label those nodes
`nvidia.com/device-plugin.config=any`. Add more keys to the ConfigMap
(`replicas: 8` for a notebook node, `replicas: 2` for a small inference
node) and point each node's label at its key.

`renameByDefault: false` keeps the resource name `nvidia.com/gpu`, and GFD
appends `-SHARED` to `nvidia.com/gpu.product`. A Kueue flavor or a
nodeSelector written for `NVIDIA-A10` will stop matching that node until
you update the label value. Set `renameByDefault: true` to advertise
`nvidia.com/gpu.shared` instead, and leave the product label alone. Pods
then request the `.shared` resource, and whole-GPU pods can keep requesting
`nvidia.com/gpu` on nodes that are not labeled for slicing.

Time-slicing is for dev boxes and several tiny models. It is a poor fit for
a training job or a latency SLO: the neighbors stall each other's kernels.

### MIG

MIG (A100, A30, H100, H200, B200, and some later data-center GPUs)
partitions one card into instances with their own memory and SM slices.
That is the hardware isolation time-slicing does not give you. Consumer
cards (4090 and non-MIG L4 SKUs) cannot do this.

A profile name is `<slices>g.<memory>gb`:

* The number before `g` is how many compute slices the instance takes. A
  full A100, H100, H200, or B200 has **7** slices. An A30 has **4**.
* The memory figure is the framebuffer reserved for that instance. A fatter
  memory profile at the same slice count fits fewer instances (H100
  `1g.10gb` × 7, or `1g.20gb` × 4).
* Instances on one card must pack: the slice counts sum to at most 7 (4 on
  an A30), and the memory must fit the card. `4g` fits once, because two
  would need 8 slices.

The operator ships these geometries as keys of `default-mig-parted-config`
in namespace `gpu-operator` (chart v25.3.2, the pin in `versions.env`).
The label value is that key:

```bash
kubectl -n gpu-operator get cm default-mig-parted-config -o yaml
kubectl label node <node> nvidia.com/mig.config=all-1g.10gb --overwrite
```

`devices: all` in every stock entry means every GPU on the node gets the
same geometry. A later operator release (v26.3+) can generate a per-node
ConfigMap from the cards it finds; the label values below stay the ones
you set. On a live node, `nvidia-smi mig -lgip` lists the profiles that
card accepts once MIG mode is on.

#### One size on every GPU (`single`)

`mig.strategy: single` (this lab's `values.yaml`) advertises every slice
as `nvidia.com/gpu: 1`, so a manifest written for a whole GPU still
schedules. Every slice on the node has to be the same profile. Pick the
row for your card. "Count" is instances **per GPU**; an 8-GPU node
advertises count × 8.

| Label | A100 40GB | A100 80GB / H100 80GB | H200 141GB | B200 |
|---|---|---|---|---|
| `all-1g.5gb` | 7 × 1g.5gb | | | |
| `all-1g.10gb` | 4 × 1g.10gb | 7 × 1g.10gb | | |
| `all-1g.18gb` | | | 7 × 1g.18gb | |
| `all-1g.23gb` | | | | 7 × 1g.23gb |
| `all-1g.20gb` | | 4 × 1g.20gb | | |
| `all-1g.35gb` | | | 4 × 1g.35gb | |
| `all-2g.10gb` | 3 × 2g.10gb | | | |
| `all-2g.20gb` | | 3 × 2g.20gb | | |
| `all-2g.35gb` | | | 3 × 2g.35gb | |
| `all-2g.45gb` | | | | 3 × 2g.45gb |
| `all-3g.20gb` | 2 × 3g.20gb | | | |
| `all-3g.40gb` | | 2 × 3g.40gb | | |
| `all-3g.71gb` | | | 2 × 3g.71gb | |
| `all-3g.90gb` | | | | 2 × 3g.90gb |
| `all-4g.20gb` | 1 × 4g.20gb | | | |
| `all-4g.40gb` | | 1 × 4g.40gb | | |
| `all-4g.71gb` | | | 1 × 4g.71gb | |
| `all-4g.90gb` | | | | 1 × 4g.90gb |
| `all-7g.40gb` | 1 × 7g.40gb (whole card, MIG still on) | | | |
| `all-7g.80gb` | | 1 × 7g.80gb | | |
| `all-7g.141gb` | | | 1 × 7g.141gb | |
| `all-7g.180gb` | | | | 1 × 7g.180gb |

An A30 24GB is a 4-slice part: `all-1g.6gb` (4), `all-2g.12gb` (2),
`all-4g.24gb` (1). H100 NVL (94GB), H100 96GB, GH200, and GB200 have
their own rows in the same ConfigMap (`all-1g.12gb`, `all-7g.94gb`,
`all-1g.24gb`, and so on). Match the key to the product string GFD already
put on the node.

A `+me` label (`all-1g.10gb.me`, and the same suffix on other small
profiles) places a single instance that also owns the card's video
decode/encode engines. The rest of the card is left empty. Use it for a
media workload.

`all-disabled` turns MIG off and returns whole GPUs. `all-enabled` turns
MIG mode on and creates no instances, so allocatable stays 0 until you
apply a real geometry.

Which row to use:

* Notebooks and 1–3B models: the smallest `1g` that exists for that card
  (`all-1g.10gb` on an 80GB A100 or H100).
* A 7B–8B in fp16/bf16 needs on the order of 16GB plus KV cache, so a
  `1g.10gb` is tight and a `2g` or the fatter `1g.20gb` / `1g.35gb` is the
  usual fit. Re-check against [docs/07](../../docs/07-model-catalog.md);
  the profile's memory is the hardware reservation, and the process sees
  less after the CUDA context.
* One big model per card: leave MIG off, or use the `7g` profile only when
  you need MIG mode on for other reasons. A `7g` instance is the whole
  card.

#### Several sizes on one card (`mixed`)

`all-balanced` puts more than one profile on each GPU, so it needs
`mig.strategy: mixed`. Pods then request the profile resource
(`nvidia.com/mig-1g.10gb: 1`), and a Deployment that asks for
`nvidia.com/gpu` will not schedule there.

| Card | `all-balanced` on each GPU |
|---|---|
| A100 40GB | 2 × 1g.5gb, 1 × 2g.10gb, 1 × 3g.20gb |
| A100 80GB / H100 80GB | 2 × 1g.10gb, 1 × 2g.20gb, 1 × 3g.40gb |
| H200 141GB | 2 × 1g.18gb, 1 × 2g.35gb, 1 × 3g.71gb |
| B200 | 2 × 1g.23gb, 1 × 2g.45gb, 1 × 3g.90gb |
| A30 24GB | 2 × 1g.6gb, 1 × 2g.12gb |

```bash
# values.yaml: mig.strategy: mixed, then upgrade the chart
kubectl label node <node> nvidia.com/mig.config=all-balanced --overwrite
kubectl get node <node> -o json | jq '.status.allocatable | with_entries(select(.key | startswith("nvidia.com/mig")))'
```

A mix of your own is a ConfigMap with one extra key, then a pointer from
the ClusterPolicy. This one fills an 80GB card (5 + 2 = 7 slices):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-mig-config
  namespace: gpu-operator
data:
  config.yaml: |
    version: v1
    mig-configs:
      five-1g-one-2g:
        - devices: all
          mig-enabled: true
          mig-devices:
            "1g.10gb": 5
            "2g.20gb": 1
```

```bash
kubectl apply -f custom-mig-config.yaml
kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge \
  -p '{"spec":{"mig":{"strategy":"mixed"},"migManager":{"config":{"name":"custom-mig-config"}}}}'
kubectl label node <node> nvidia.com/mig.config=five-1g-one-2g --overwrite
```

Set `devices: [0, 1]` instead of `all` to partition only those GPU indexes
and leave the others out of that entry. Copy `all-disabled` into the custom
ConfigMap too, or that label disappears when the manager stops reading the
default map.

#### What the apply does

MIG Manager cordons GPU client pods (device plugin, GFD, DCGM exporter),
stops host processes that hold the GPU when the driver is preinstalled,
applies the geometry, and starts the clients again. Enabling MIG mode can
reboot the node. Drain it first, and expect `nvidia.com/gpu` capacity to
drop to 0 until the device plugin re-registers the slices. With a
preinstalled driver the manager also restarts the host services listed in
`default-gpu-clients`.

GFD then rewrites `nvidia.com/gpu.product` to include the profile, for
example `NVIDIA-H100-80GB-HBM3-MIG-1g.10gb`. A Kueue flavor or nodeSelector
written for the bare product string stops matching until you update it.
With `single` and `all-1g.10gb`, an 8-GPU node advertises 56
`nvidia.com/gpu`. Raise the ClusterQueue quota to that number, or Kueue
will keep admitting only the old whole-GPU count. With `mixed`, the quota
has to list `nvidia.com/mig-1g.10gb` (and the other profile resources),
because `nvidia.com/gpu` is no longer the thing being served.

### MPS

MPS (Multi-Process Service) is a third sharing mode in the same device
plugin ConfigMap: a per-GPU MPS daemon, and `replicas` CUDA clients with a
thread percentage. Isolation is stronger than time-slicing and weaker than
MIG. This lab does not ship an MPS ConfigMap. Use it when many small
inference processes share a card and you can accept an MPS daemon on the
node. The ConfigMap shape is the time-slicing file with a `sharing.mps`
block instead of `sharing.timeSlicing`.

## What this folder does not do

Kueue decides whether a job may consume a GPU from a quota. KAI decides
which node and which device a pod lands on, including a fractional request.
HAMi, in [`platform/11-hami`](../11-hami/README.md), is the path that
enforces a memory and compute cap inside the container, and the path that
covers AMD GPUs later. DRA (Kubernetes 1.34+, NVIDIA DRA driver) is the
longer-term replacement for the device-plugin resource; the comparison is
in [docs/03](../../docs/03-hardware-and-cluster-prereqs.md).

| Need | Use |
|---|---|
| One container, one whole GPU | this folder, default |
| Several untrusted pods, hard memory split, data-center GPU | MIG |
| Several tiny dev pods, no isolation | time-slicing |
| "Half a GPU" as a scheduler decision, lab only | KAI `gpu-fraction` (`platform/10-kai-scheduler`) |
| A memory cap the process cannot exceed, or an AMD GPU | HAMi |
