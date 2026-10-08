# 01 — Architecture

All diagrams are Mermaid, so they render on GitHub and in most Markdown
viewers.

## 1. Layered view

```mermaid
flowchart TB
  client([Clients: apps, SDKs, notebooks, eval jobs])

  subgraph GW["Gateway layer — ns: ai-gateway / envoy-gateway-system"]
    EG[Envoy proxy<br/>LoadBalancer IP via Cilium LB-IPAM]
    AIGW[Envoy AI Gateway controller<br/>AIGatewayRoute / AIServiceBackend]
    SEC[SecurityPolicy: API key or JWT Keycloak<br/>BackendTrafficPolicy: token budgets]
  end

  subgraph RT["Routing layer — ns: llm-serving"]
    PSR[vLLM production-stack router<br/>roundrobin / session / prefix / kv-aware]
    EPP[Inference Extension EPP<br/>InferencePool, queue + KV aware]
  end

  subgraph SV["Serving layer — ns: llm-serving"]
    V1[vLLM chat engines ×N]
    V2[vLLM embeddings / reranker]
    V3[vLLM VLM / MoE / TP]
    V4[vLLM multi-node LWS]
    RS[Ray Serve LLM RayService]
    LMC[(LMCache server / Valkey<br/>shared KV tier)]
  end

  subgraph TR["Training layer — ns: training, mlops"]
    KQ[Kueue]
    TJ[Kubeflow TrainJob → JobSet]
    RJ[KubeRay RayJob / RayCluster]
    MLF[MLflow]
    S3[(MinIO S3<br/>datasets / checkpoints / adapters)]
  end

  subgraph PL["Platform layer"]
    CIL[Cilium + Hubble]
    GPUOP[NVIDIA GPU Operator<br/>device plugin, DCGM, MIG]
    PROM[Prometheus + Grafana]
    KEDA[KEDA]
    LWS[LeaderWorkerSet]
    NFS[(RWX model cache<br/>NFS)]
  end

  client --> EG
  AIGW -. configures .-> EG
  SEC -. attached to .-> EG
  EG -->|model = llama / qwen / bge| PSR
  EG -->|model = qwen3| EPP
  EG -->|model = raw / ray| V3 & RS
  PSR --> V1 & V2
  EPP --> V1
  V1 <--> LMC
  V1 & V2 & V3 & V4 --> NFS
  KQ --> TJ & RJ
  TJ & RJ --> S3 & MLF
  S3 -->|LoRA adapters| V3
  PROM -->|vllm:num_requests_waiting| KEDA -->|scale| V1
  GPUOP -->|nvidia.com/gpu| SV & TR
  LWS --> V4
```

## 2. Namespaces and who owns what

| Namespace | Contents | Installed by |
|---|---|---|
| `kube-system` | Cilium, Hubble | `platform/00-cilium` |
| `cert-manager` | cert-manager, lab CA | `platform/03` |
| `nfs-provisioner` | NFS RWX provisioner | `platform/04` |
| `gpu-operator` | NVIDIA operator stack | `platform/05` |
| `monitoring` | Prometheus, Grafana, Alertmanager | `platform/06` |
| `keda`, `lws-system`, `kueue-system` | operators | `platform/07–09` |
| `envoy-gateway-system` | Envoy Gateway controller **and the Envoy proxy pods** | `gateway/01` |
| `envoy-ai-gateway-system` | AI Gateway controller (extension server) | `gateway/02` |
| `ai-gateway` | `Gateway`, `AIGatewayRoute`s, backends, auth policies | `gateway/03` |
| `llm-serving` | vLLM, routers, LMCache, EPP, RayService | `inference/*` |
| `training` | TrainJobs, RayJobs, dev RayCluster, LocalQueue `research` | `training/*` |
| `mlops` | MinIO, MLflow | `training/01–02` |
| `evaluation` | benchmark & eval Jobs, LocalQueue `batch` | `evaluation/*` |
| `security` | Keycloak, OpenBao, Falco | `security/*` |

## 3. Life of an inference request

```mermaid
sequenceDiagram
  autonumber
  participant C as Client (OpenAI SDK)
  participant E as Envoy proxy (AI Gateway)
  participant X as AI GW ext_proc
  participant R as Stack router / EPP
  participant V as vLLM engine (pod k)
  participant L as LMCache (CPU / remote)

  C->>E: POST /v1/chat/completions {model:"lab-chat", stream:true}<br/>x-api-key or Bearer JWT
  E->>E: SecurityPolicy: authenticate, map claims → x-user-id
  E->>X: body for inspection
  X-->>E: set x-ai-eg-model=lab-chat, rewrite model → Qwen/... (alias)
  E->>E: AIGatewayRoute match → backend vllm-stack<br/>rate-limit check (token budget for x-user-id)
  E->>R: forward request
  R->>R: pick engine: same prefix/session → pod k<br/>(or EPP: lowest queue + highest KV hit)
  R->>V: forward
  V->>V: hash prompt blocks → prefix cache hit in GPU?
  alt miss in GPU
    V->>L: lookup KV chunks (CPU RAM → remote)
    L-->>V: KV chunks (skip prefill for them)
  end
  V->>V: prefill remaining tokens, then decode<br/>(continuous batching with other requests)
  V-->>C: SSE token stream (via router, Envoy)
  V->>L: store new KV chunks (async)
  E->>E: on completion: usage tokens → metadata<br/>charge token budget, emit metrics/logs
```

Where latency goes:

* **TTFT** (time to first token) = queueing + prefill. Prefix caching and
  LMCache attack the prefill part. Autoscaling and routing attack queueing.
* **TPOT/ITL** (time per output token) = decode step time. It depends on
  batch size, model size, memory bandwidth, speculative decoding and
  parallelism.

## 4. Two levels of routing, and why both

```mermaid
flowchart LR
  subgraph L1["Level 1 — Gateway (Envoy AI Gateway)"]
    direction TB
    A1[Who are you? auth]
    A2[Which model/provider? model → backend]
    A3[Are you within budget? token rate limit]
    A4[Backend down? fallback by priority]
  end
  subgraph L2["Level 2 — Inference-aware (router / EPP)"]
    direction TB
    B1[Which replica has my KV cache?]
    B2[Which replica has the shortest queue?]
    B3[Which replica has my LoRA loaded?]
    B4[Prefill pool vs decode pool?]
  end
  L1 --> L2 --> P[(vLLM pods)]
```

Level 1 is about **tenants and providers**. Level 2 is about **GPU
efficiency**. A plain Kubernetes Service (random L4 balancing) destroys
cache locality, and at scale that is the difference between, for example,
a 200 ms and a 2 s TTFT on long-context traffic.

## 5. KV-cache hierarchy (LMCache)

```mermaid
flowchart TB
  subgraph Pod1["vLLM pod A"]
    G1[GPU HBM: paged KV blocks<br/>fastest, smallest]
    C1[CPU DRAM pinned buffer<br/>LMCache local_cpu]
    D1[Local NVMe<br/>LMCache local_disk]
  end
  subgraph Pod2["vLLM pod B"]
    G2[GPU HBM]
    C2[CPU DRAM]
  end
  R[(Remote shared KV<br/>LMCache server / Valkey / Mooncake)]
  G1 <-->|evict / reload| C1 <--> D1
  C1 <-->|put / get chunks| R
  C2 <-->|reuse KV computed by pod A| R
  G2 <--> C2
```

## 6. Training and the train → serve loop

```mermaid
flowchart LR
  U[Researcher] -->|kubectl apply / SDK| TJ[TrainJob or RayJob<br/>label: queue-name=research]
  TJ --> KQ{Kueue<br/>quota available?}
  KQ -- no --> W[Pending / may preempt lower priority]
  KQ -- yes --> ADM[Admitted → pods created<br/>all-or-nothing]
  ADM --> SCH[kube-scheduler → GPU nodes]
  SCH --> RUN[torchrun / Ray Train<br/>NCCL over Cilium or RDMA]
  RUN -->|metrics| MLF[MLflow]
  RUN -->|checkpoints / adapters| S3[(MinIO)]
  S3 -->|initContainer sync| VL[vLLM --enable-lora]
  VL --> GW[AI Gateway route]
  GW --> EV[lm-eval Job via Kueue 'batch']
  EV -->|scores| MLF
  EV -->|pass| PROMOTE[Promote: alias lab-chat → new model]
```

## 7. Control loops at a glance

| Loop | Watches | Acts on |
|---|---|---|
| GPU Operator | node hardware | installs driver/toolkit, advertises `nvidia.com/gpu` |
| Kueue | queued Workloads + quotas | unsuspends jobs, preempts lower priority |
| KEDA | Prometheus vLLM metrics | HPA replica count of vLLM Deployments |
| Ray autoscaler | Ray resource demand | RayCluster worker pod count |
| Envoy Gateway + AI GW | Gateway API + AI CRDs | Envoy xDS config |
| Inference Extension EPP | vLLM pod metrics | per-request endpoint choice |
| LWS | group pod health | recreates entire leader+worker group |
| ESO | OpenBao secrets | Kubernetes Secrets |
| Kyverno / Falco | API requests / syscalls | policy reports, alerts |
