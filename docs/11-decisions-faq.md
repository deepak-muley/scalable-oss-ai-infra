# 11 — Design decisions and FAQ

## Do I need Istio (or another service mesh)?

**No, not for this lab, and probably not until you have real multi-tenant
east-west security requirements.** What a mesh would give you is already
covered:

| Mesh feature | Covered here by |
|---|---|
| North-south gateway, routing, auth, rate limiting | Envoy Gateway + Envoy AI Gateway |
| L3/L4 (and L7) network policy between namespaces | Cilium NetworkPolicy (`platform/00-cilium/netpol-llm-serving.yaml`) |
| Encryption in transit between nodes | Cilium WireGuard (`encryption.enabled`) |
| Traffic visibility, service map, HTTP golden signals | Hubble + Envoy + vLLM metrics |
| Smart load balancing to model pods | stack router / Inference Extension (a mesh's LB isn't KV-cache aware anyway) |

Reasons *not* to add one now:

* **Sidecars and GPU workloads mix poorly.** They add a hop and buffering
  to long SSE streams, interfere with NCCL and multi-node rendezvous (ports,
  init ordering), complicate Job/RayJob completion (the sidecar keeps the
  pod alive), and add memory per pod.
* It's one more control plane to learn and upgrade, and its value is mostly
  in microservice estates, not GPU fleets.

When you *would* add one:

* You need **workload-identity mTLS** with authorization policies between
  many services (zero-trust compliance). Consider **Istio ambient mode**
  (no sidecars: a per-node ztunnel for L4 mTLS, optional waypoints for L7)
  or **Cilium mutual authentication** (SPIFFE-based).
* You want Istio as the Gateway API implementation for the Inference
  Extension. That's supported, but Envoy Gateway does the same job here.
* Exclude training namespaces and NCCL traffic from the mesh regardless.

## Envoy AI Gateway vs LiteLLM vs kgateway

* **Envoy AI Gateway**: Kubernetes-native (Gateway API CRDs), Envoy data
  plane performance, InferencePool integration, token rate limiting.
  Picked because it composes with the k8s inference stack.
* **LiteLLM proxy**: Python, very broad provider coverage, built-in key
  management, budgets and UI. Great for teams that mostly call external
  APIs. It can sit behind Envoy if you want both.
* **kgateway** (formerly Gloo, now CNCF): another Envoy-based Gateway API
  implementation with AI features and GIE support.

## production-stack router vs Inference Extension vs llm-d

| | production-stack | GIE (EPP) | llm-d |
|---|---|---|---|
| What | Helm chart: engines + Python router + LMCache | k8s API + endpoint picker plugged into any conformant gateway | full distributed-inference stack built on GIE |
| Cache awareness | prefix / session / KV-aware via LMCache controller | prefix scorer + queue/KV/LoRA metrics | KV-cache indexer with precise prefix tracking |
| P/D disaggregation | yes (LMCache) | building block | first-class (NIXL) |
| Best for | learning, small/medium labs | the standard k8s way; any gateway | large deployments, MoE wide-EP |

This repo teaches the first two. llm-d is the natural next step, and its
"well-lit path" guides assume the same pieces (GIE, LWS, vLLM, Prometheus).

## KServe? NVIDIA Dynamo? AIBrix?

All are valid **higher-level platforms** over the same primitives:

* **KServe**: `InferenceService` abstraction, multi-framework (sklearn to
  LLMs), a CNCF project, adding llm-d integration. Pick it if you also serve
  classic ML models.
* **NVIDIA Dynamo**: OSS distributed-inference framework (P/D, KV-aware
  routing, NIXL, multi-engine: vLLM, SGLang and TRT-LLM), with a
  Kubernetes operator. It's NVIDIA-optimized.
* **AIBrix**: ByteDance's vLLM control plane (LoRA management, KV-aware
  routing, autoscaling).

Learn the primitives here first, then adopt one if it fits.

## Kueue vs Volcano vs Slurm

* **Kueue** (SIG Scheduling) works *with* the default scheduler; it decides
  admission, not placement. It supports TrainJob, RayJob, JobSet, LWS and
  plain Pods, plus MultiKueue and TAS. It has the most momentum in upstream
  Kubernetes.
* **Volcano** replaces the scheduler (gang scheduling, queues, many
  plugins) and is widely used in China and in HPC-style shops.
* **Slurm** remains the HPC standard. **Slinky** (SchedMD) and SUNK
  (CoreWeave) run Slurm on Kubernetes when researchers want `sbatch`.

## Cilium LB-IPAM vs MetalLB

Since Cilium is already the CNI, its LB-IPAM and L2/BGP announcements avoid a
second component. MetalLB stays in `platform/02-metallb` for clusters using a
different CNI.

## Why vLLM (and not SGLang / TRT-LLM)?

vLLM has the broadest model and hardware support, the integrations used
here (production-stack, LMCache, GIE, Ray Serve LLM, llm-d) and a fast
release cadence. **SGLang** is an excellent alternative (RadixAttention,
strong DeepSeek/MoE performance) and fits the same slots: gateway, LWS and
Kueue all stay the same. Try swapping one model to SGLang as an exercise.

## Why NFS for weights?

It's simple and RWX. At larger scale move to a parallel FS, object
streaming (Run:ai streamer from S3) and node-local NVMe pre-staging (docs/10).

## Why not one giant Helm umbrella chart?

For learning, each component's install is explicit and readable. For
operating, wrap the same folders as Argo CD Applications
(an ApplicationSet over `platform/*`, `gateway/*` and so on).
