# Cilium — CNI, kube-proxy replacement, LoadBalancer IPs, Hubble

[Cilium](https://cilium.io) is the pod network for this lab. It is eBPF-based
and replaces several components at once:

| Cilium feature | Replaces / adds | Why it matters for AI infra |
|---|---|---|
| CNI (eBPF datapath) | flannel/calico | high-throughput pod networking for multi-GB model/KV transfers |
| `kubeProxyReplacement=true` | kube-proxy (iptables) | O(1) service lookups; scales with many model Services/endpoints |
| **LB-IPAM + L2 announcements** | MetalLB | real LAN IPs for the AI gateway `Service type=LoadBalancer` |
| **Hubble** (+ UI) | – | see every flow gateway→router→vLLM, latency, drops, DNS |
| NetworkPolicy / CiliumNetworkPolicy (L3–L7) | – | isolate tenants/namespaces; only the gateway may reach vLLM |
| Bandwidth manager / BBR | – | fairer egress for big downloads (HF weights, checkpoints) |
| Gateway API (optional) | – | **disabled here**: we use Envoy Gateway for the AI gateway; both can coexist with different GatewayClasses |

## Install (new cluster)

Cilium must be the CNI from day one. Bootstrap the cluster **without** a CNI
and **without kube-proxy**:

```bash
# kubeadm
kubeadm init --skip-phases=addon/kube-proxy --pod-network-cidr=10.244.0.0/16
# k3s:   --flannel-backend=none --disable-network-policy --disable-kube-proxy
# RKE2:  cni: none, disable-kube-proxy: true

API_SERVER_IP=<control-plane ip or VIP> ./install.sh
cilium status --wait            # optional: brew install cilium-cli
vi lb-ipam.yaml && kubectl apply -f lb-ipam.yaml
```

Existing cluster with another CNI? Migrating CNIs live is possible (Cilium
has a migration guide) but disruptive — for a lab, rebuilding is simpler.

## GPU / multi-node training networking

Cilium carries the *pod* network (control traffic, HTTP, NCCL over TCP for
small jobs). For serious multi-node training, NCCL wants **RDMA**
(InfiniBand or RoCE) via **GPUDirect RDMA**. That is added as a *secondary*
network next to Cilium:

```
Pod eth0  ──► Cilium (k8s services, gateway traffic, metrics)
Pod net1  ──► Multus + SR-IOV / host-device / ipoib CNI ──► IB/RoCE NIC  (NCCL)
```

managed by the **NVIDIA Network Operator** (MOFED drivers, RDMA shared
device plugin, Multus, Whereabouts IPAM). See docs/03-hardware-and-cluster-prereqs.md.

## Observe

```bash
cilium hubble port-forward &
hubble observe -n llm-serving --protocol http
kubectl -n kube-system port-forward svc/hubble-ui 12000:80
```
