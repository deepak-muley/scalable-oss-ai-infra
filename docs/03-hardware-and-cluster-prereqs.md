# 03 — Hardware and cluster prerequisites

## Minimum useful labs

| Tier | Hardware | What you can do |
|---|---|---|
| **0 — laptop** | 8 CPU / 16 GB RAM, Docker | everything control-plane in `kind/` (simulated GPUs) |
| **1 — single GPU box** | 1× 16–24 GB GPU (RTX 4090 / L4 / A10), 64 GB RAM, 1 TB NVMe | vLLM basics, LMCache, small production stack, LoRA fine-tune, KEDA |
| **2 — multi-GPU node** | 4–8× 24–80 GB GPUs, ideally NVLink, 256–512 GB RAM | multi-model serving, 70B with TP, MoE with EP, DDP/FSDP, Kueue contention |
| **3 — multi-node** | 2+ GPU nodes plus 25–100 GbE (RoCE ideal) or InfiniBand | multi-node training (NCCL), 405B or DeepSeek via LWS, real disaggregation |

Keep a small **CPU-only system node** or two for control-plane add-ons
(Prometheus, gateway, Keycloak, MinIO) so they don't steal GPU-node RAM.

## Host OS checklist (GPU nodes)

* Ubuntu 22.04/24.04 or RHEL 9. Kernel ≥ 5.10 (≥ 5.8 for Falco modern eBPF;
  Cilium likes ≥ 5.10).
* Either let the GPU Operator install the driver (`DRIVER_ENABLED=true`) or
  pre-install a datacenter driver (`nvidia-driver-5xx-server`). Don't mix the
  two.
* Disable swap. Set `vm.max_map_count` high if you use Ray. Make sure
  `/var/lib/containerd` sits on fast NVMe with 500 GB+ free, because
  vLLM/PyTorch images are 10–20 GB.
* Use the containerd runtime. The GPU Operator toolkit configures the
  `nvidia` runtime class.
* Optional but valuable: enable persistence mode, and for MIG-capable GPUs
  decide your MIG layout up front.

## Kubernetes bootstrap with Cilium

```bash
# kubeadm (each control-plane / worker: containerd + kubeadm/kubelet installed)
sudo kubeadm init --skip-phases=addon/kube-proxy --pod-network-cidr=10.244.0.0/16
# join workers, then:
API_SERVER_IP=<cp-ip> ./platform/00-cilium/install.sh
```

* k3s: `--flannel-backend=none --disable-network-policy --disable-kube-proxy --disable servicelb --disable traefik`
* RKE2: `cni: none`, `disable-kube-proxy: true`, `disable: [rke2-ingress-nginx]`

Kubernetes ≥ **1.31** is recommended. **1.34+** adds GA Dynamic Resource
Allocation (DRA), the future model for GPU requests (see below).

## Networking

| Traffic | Bandwidth need | Recommended |
|---|---|---|
| Gateway ↔ routers ↔ vLLM (HTTP/SSE) | low | Cilium pod network |
| Model weight loading (NFS/S3 → nodes) | bursty, high (an 8B model is 16 GB; a 70B model is 140 GB) | 25 GbE+ to storage; local NVMe cache |
| KV-cache transfer (LMCache remote, P/D disaggregation) | high, latency-sensitive | 100 GbE+ / RDMA (NIXL, Mooncake) |
| NCCL all-reduce (multi-node training, PP/TP across nodes) | **very high** | InfiniBand or RoCEv2 with **GPUDirect RDMA**, 1 NIC per GPU at scale |

To add RDMA alongside Cilium, install the **NVIDIA Network Operator**. It
provides MOFED/DOCA drivers, an RDMA shared device plugin or SR-IOV, Multus
for secondary interfaces and Whereabouts IPAM. Training pods then request
`rdma/rdma_shared_device_a: 1` and get a `net1` interface for NCCL
(`NCCL_IB_HCA`, `NCCL_SOCKET_IFNAME=eth0` for bootstrap). Cilium stays the
primary CNI.

## Storage layout

```
NFS (RWX)    /export/k8s/llm-serving-model-cache-.../hf/...   ← shared HF cache (all vLLM pods)
MinIO (S3)   datasets/  checkpoints/  mlflow/  models/
Local NVMe   containerd images, LMCache local_disk, Ray spill, /tmp for training
```

## GPU sharing options

| Mechanism | Isolation | Use |
|---|---|---|
| Whole GPU | full | default for serving and training |
| **MIG** (A100/H100/H200/B200) | hardware: memory + SMs | many small models, multi-tenant notebooks |
| **Time-slicing** | none (shared memory) | dev and test, several tiny models on consumer GPUs |
| **MPS** | partial | many small inference processes |
| **DRA** (Dynamic Resource Allocation, k8s 1.34+ GA, NVIDIA DRA driver) | per device, rich selectors | request "a GPU with ≥ 40 GB and NVLink to this other one", share via claims; replaces device-plugin semantics over time |

## Labels you'll use (from GPU Feature Discovery)

```bash
kubectl get nodes -L nvidia.com/gpu.product,nvidia.com/gpu.memory,nvidia.com/gpu.count,nvidia.com/mig.capable
```

Use them in Kueue `ResourceFlavor`s (`platform/09-kueue/queues.yaml`) and
in `nodeSelector`s for big-model deployments.
