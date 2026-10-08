# 02 — OSS component catalog

Every component is open source. "Alt" lists credible OSS alternatives worth
knowing. Licences are as of writing; check before commercial use.

## Platform

| Component | Role in this lab | Interacts with | Alt | Licence |
|---|---|---|---|---|
| **Kubernetes** (≥1.31) | substrate | everything | – | Apache-2.0 |
| **Cilium** | CNI, kube-proxy replacement, LoadBalancer IPs (LB-IPAM + L2), NetworkPolicy L3–L7, WireGuard, Hubble flow visibility | every pod; Envoy proxy Service gets its IP from Cilium | Calico, Flannel (+MetalLB) | Apache-2.0 |
| **MetalLB** (optional) | LB IPs when not using Cilium LB-IPAM | Services | kube-vip | Apache-2.0 |
| **cert-manager** | TLS certs, lab CA, webhook certs | Gateway HTTPS listeners, operators | – | Apache-2.0 |
| **NFS subdir provisioner** | RWX `nfs-client` StorageClass for model cache | vLLM pods, download job | Longhorn, Rook-Ceph (CephFS), JuiceFS | Apache-2.0 |
| **NVIDIA GPU Operator** | driver, container toolkit, device plugin, GFD labels, DCGM exporter, MIG manager | kubelet, Prometheus, Kueue flavors (labels) | (manual install of the same pieces); AMD GPU Operator for AMD | Apache-2.0 |
| **kube-prometheus-stack** | Prometheus, Alertmanager, Grafana | DCGM, vLLM, Envoy, Kueue, Ray metrics; KEDA queries it | VictoriaMetrics, Thanos/Mimir at scale | Apache-2.0 / AGPL (Grafana) |
| **KEDA** | autoscale on Prometheus queries, cron, scale-to-zero | vLLM Deployments (via HPA) | HPA + prometheus-adapter, Knative | Apache-2.0 |
| **LeaderWorkerSet** | a "replica" spanning multiple pods/nodes | vLLM multi-node, llm-d, Kueue | JobSet (batch), RayCluster | Apache-2.0 |
| **Kueue** | quotas, queues, cohorts/borrowing, priorities, preemption, gang admission | TrainJob, RayJob, Job, JobSet, LWS | Volcano, YuniKorn, Slurm (Slinky/SUNK on k8s) | Apache-2.0 |

## Gateway and routing

| Component | Role | Interacts with | Alt | Licence |
|---|---|---|---|---|
| **Gateway API** | standard CRDs: `GatewayClass`, `Gateway`, `HTTPRoute` | Envoy Gateway implements it | Ingress (legacy) | Apache-2.0 |
| **Envoy Gateway** | Gateway API controller; runs the Envoy proxies; security, rate limit and traffic policies | AI Gateway (extension server), Redis (rate limits), Keycloak (JWKS) | kgateway, Istio gateway, Cilium Gateway, NGINX Gateway Fabric | Apache-2.0 |
| **Envoy AI Gateway** | LLM-aware edge: unified OpenAI API, model routing via body parsing, aliases, provider translation (OpenAI/Anthropic/Bedrock/Vertex/Azure), upstream credential injection, token usage and limits, fallback | Envoy Gateway, vLLM routers, InferencePool, external providers | **LiteLLM proxy**, kgateway AI, Kong AI Gateway (OSS core), Higress | Apache-2.0 |
| **Gateway API Inference Extension** | `InferencePool` + Endpoint Picker: per-request pod selection using queue depth, KV-cache usage, prefix affinity, LoRA affinity | Envoy (ext_proc), vLLM `/metrics` | production-stack router; llm-d (built on it) | Apache-2.0 |
| **vLLM production-stack router** | OpenAI-compatible router: model discovery via k8s labels; roundrobin, session, prefix-aware and KV-aware routing (LMCache controller); disaggregated prefill | vLLM engines, LMCache | GIE EPP, llm-d, SGLang router, NVIDIA Dynamo router | Apache-2.0 |
| **vLLM Semantic Router** (optional, docs only) | picks a model by request *intent* (e.g. math→reasoning model, chit-chat→small model) | sits in front of models / in Envoy ext_proc | RouteLLM | Apache-2.0 |

## Inference

| Component | Role | Notes | Alt | Licence |
|---|---|---|---|---|
| **vLLM** | model server: PagedAttention, continuous batching, prefix caching, chunked prefill, speculative decoding, quantization (FP8/AWQ/GPTQ/INT4), TP/PP/EP/DP, LoRA multiplexing, OpenAI API, embeddings, reranking, multimodal | the core engine everywhere here | **SGLang**, TensorRT-LLM, TGI (maintenance), llama.cpp, Ollama (dev) | Apache-2.0 |
| **LMCache** | KV-cache engine: offload to CPU/disk, share across replicas (remote server/Valkey/Mooncake/S3), KV transfer for P/D disaggregation | vLLM KV connector `LMCacheConnectorV1` | Mooncake, NIXL (transport), vLLM native CPU offload | Apache-2.0 |
| **llm-d** (docs) | Kubernetes-native distributed inference: GIE scheduler + vLLM + P/D disaggregation + wide expert parallelism + KV-cache-aware routing; from Red Hat, Google, IBM, NVIDIA, CoreWeave and others | composes GIE, LWS, vLLM, NIXL | NVIDIA **Dynamo**, AIBrix (ByteDance), KServe LLMInferenceService | Apache-2.0 |
| **KServe** (docs) | model-serving platform (`InferenceService`), now with LLM features, uses vLLM | alternative control plane | Seldon Core (BSL now), BentoML | Apache-2.0 |
| **Ray Serve LLM** | Python-composable serving on Ray; vLLM inside | KubeRay `RayService` | – | Apache-2.0 |
| **llm-d-inference-sim** | fake vLLM (API + metrics) for testing without GPUs | `kind/` | – | Apache-2.0 |

## Training and MLOps

| Component | Role | Notes | Alt | Licence |
|---|---|---|---|---|
| **Kubeflow Trainer v2** | `TrainJob` + `ClusterTrainingRuntime` (torch, DeepSpeed, MLX, torchtune); built on **JobSet** | env for torchrun injected | Training Operator v1 (`PyTorchJob`), Volcano jobs | Apache-2.0 |
| **KubeRay** | `RayCluster`, `RayJob`, `RayService` | Ray Train, Ray Data, RL frameworks, Ray Serve | – | Apache-2.0 |
| **PyTorch** + FSDP2 / DDP | training framework | in job images | JAX (+ MaxText) | BSD |
| **torchtitan / Megatron-LM / DeepSpeed** (docs) | large-scale pretraining (3D–5D parallelism) | needed beyond a few nodes | NeMo, Nanotron | BSD / Apache / MIT |
| **veRL / OpenRLHF / NeMo-RL / SkyRL** (docs) | RL post-training: trainer + vLLM/SGLang rollouts on Ray | KubeRay | TRL (single-node friendly) | Apache-2.0 |
| **MLflow** | experiment tracking, model registry | jobs log here; artifacts in MinIO | Aim, ClearML, W&B (SaaS) | Apache-2.0 |
| **MinIO** | S3 object store | see licensing note in `training/01` | SeaweedFS, Garage, Ceph RGW | AGPL-3.0 |

## Evaluation

| Component | Role | Alt |
|---|---|---|
| **vllm bench serve** | latency and throughput benchmarking | GuideLLM, genai-perf, k6 |
| **lm-evaluation-harness** | academic benchmarks against any OpenAI-compatible endpoint | OpenCompass, lighteval, Inspect (UK AISI), HELM |

## Security

| Component | Role | Alt | Licence |
|---|---|---|---|
| **Keycloak** | OIDC IdP, SSO, service accounts | Dex, Authentik, Zitadel | Apache-2.0 |
| **OpenBao** | secrets manager (Vault API) | Infisical, Vault (BSL) | MPL-2.0 |
| **External Secrets Operator** | sync secrets into k8s | Secrets Store CSI driver | Apache-2.0 |
| **Kyverno** | admission policy | OPA Gatekeeper, ValidatingAdmissionPolicy | Apache-2.0 |
| **Falco** | runtime detection | Tetragon, Tracee | Apache-2.0 |
| **Trivy Operator** | CVE, misconfig, secret scans, SBOM | Grype/Syft, Kubescape | Apache-2.0 |
| **Sigstore cosign** | image signing and verification | Notation | Apache-2.0 |
| **Llama Guard / NeMo Guardrails / Presidio** | AI safety classification, rails, PII | Granite Guardian, ShieldGemma | various open licences |

## Do I need Istio?

**No, not for this lab.** See [docs/11](11-decisions-faq.md#do-i-need-istio-or-another-service-mesh) for when you might add it.
