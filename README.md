# scalable-oss-ai-infra

A **learning lab** for building a frontier-lab-style AI platform (scalable
**inference** for many model types + distributed **training/fine-tuning**)
on Kubernetes using **only open-source software**, from a laptop (kind) to
a GPU lab, with the path to hyperscale documented.

```
                    clients (OpenAI SDK / curl / apps / eval jobs)
                                      │  JWT / API key
┌─────────────────────────────────────▼──────────────────────────────────────┐
│ GATEWAY      Envoy Gateway + Envoy AI Gateway   (auth, model routing,      │
│              token rate-limits, aliases, fallback, usage metrics)          │
├────────────────────────────────────┬───────────────────────────────────────┤
│ ROUTING      vLLM production-stack │ Gateway API Inference Extension (EPP) │
│              router (prefix/KV-    │ / llm-d scheduler (queue + KV-cache   │
│              aware, LMCache ctrl)  │ aware endpoint picking)               │
├────────────────────────────────────┴───────────────────────────────────────┤
│ SERVING      vLLM engines (chat, embeddings, rerank, VLM, MoE, 70B TP,     │
│              405B multi-node via LWS, LoRA adapters, Ray Serve LLM)        │
│              LMCache: KV cache GPU→CPU→disk→shared remote                  │
├────────────────────────────────────────────────────────────────────────────┤
│ TRAINING     Kueue (quota/queues/preemption) · Kubeflow Trainer (TrainJob) │
│              KubeRay (RayJob/RayCluster/RayService) · MLflow · MinIO (S3)  │
├────────────────────────────────────────────────────────────────────────────┤
│ SECURITY     Keycloak · OpenBao + External Secrets · Kyverno · Falco ·     │
│              Trivy · Cilium NetworkPolicy/WireGuard · Llama Guard          │
├────────────────────────────────────────────────────────────────────────────┤
│ PLATFORM     Cilium (CNI, no kube-proxy, LB-IPAM, Hubble) · NVIDIA GPU     │
│              Operator · cert-manager · NFS/RWX storage · Prometheus/Grafana│
│              · KEDA · LeaderWorkerSet                                      │
└────────────────────────────────────────────────────────────────────────────┘
                     Kubernetes on GPU nodes (or kind with simulated GPUs)
```

## Start here

> **New here? Follow the guided reading order in [docs/README.md](docs/README.md)**,
> which takes you week by week from the big picture to running your own
> model lifecycle. The table below is a by-topic lookup.

| If you want to… | Go to |
|---|---|
| Understand the big picture & how a frontier lab maps to OSS | [docs/00-vision-frontier-lab-on-oss.md](docs/00-vision-frontier-lab-on-oss.md) |
| See the architecture diagrams & request/training flows | [docs/01-architecture.md](docs/01-architecture.md) |
| Know every OSS component, why it's here, and alternatives | [docs/02-oss-components.md](docs/02-oss-components.md) |
| **Try it on a laptop now** (kind, no GPU) | [kind/README.md](kind/README.md) |
| Prepare GPU hardware & the cluster | [docs/03-hardware-and-cluster-prereqs.md](docs/03-hardware-and-cluster-prereqs.md) |
| Install on your GPU lab, step by step | [docs/04-install-runbook.md](docs/04-install-runbook.md) |
| Learn inference internals (vLLM, LMCache, routing, autoscaling) | [docs/05-inference-deep-dive.md](docs/05-inference-deep-dive.md) |
| Learn distributed training (parallelism, Kueue, Ray, RL) | [docs/06-training-deep-dive.md](docs/06-training-deep-dive.md) |
| Size models to GPUs | [docs/07-model-catalog.md](docs/07-model-catalog.md) |
| Observe it | [docs/08-observability.md](docs/08-observability.md) |
| A guided sequence of hands-on labs | [docs/09-learning-path.md](docs/09-learning-path.md) |
| **Go from lab to hyperscale** | [docs/10-scaling-to-hyperscale.md](docs/10-scaling-to-hyperscale.md) |
| Design decisions (Istio? KServe? Volcano? llm-d?) | [docs/11-decisions-faq.md](docs/11-decisions-faq.md) |
| Secure it | [docs/12-security.md](docs/12-security.md) |
| Fix it | [docs/13-troubleshooting.md](docs/13-troubleshooting.md) |
| **Build your own model**: data → pretrain → SFT → RL (GRPO) → eval gate → serve | [docs/14-build-your-own-model.md](docs/14-build-your-own-model.md) · [`lifecycle/`](lifecycle/) |
| Run the platform with GitOps and automate model releases | [docs/15-gitops-and-pipelines.md](docs/15-gitops-and-pipelines.md) |
| Dashboards, SLO alerts, tracing, logs, cost per token | [docs/16-advanced-observability.md](docs/16-advanced-observability.md) |
| Failure drills, chaos engineering, GPU health automation | [docs/17-reliability-and-chaos.md](docs/17-reliability-and-chaos.md) |
| Capacity planning and onboarding tenants | [docs/18-capacity-planning-and-tenancy.md](docs/18-capacity-planning-and-tenancy.md) |
| llm-d P/D disaggregation, SGLang, speculative decoding | [docs/19-advanced-serving.md](docs/19-advanced-serving.md) |
| Build apps on it: chat UI, RAG, agents + MCP, batch API, notebooks | [docs/20-apps-and-workbench.md](docs/20-apps-and-workbench.md) |
| Day-2: backups, upgrades, image pre-pull, multi-cluster (MultiKueue) | [docs/21-day2-ops-and-multicluster.md](docs/21-day2-ops-and-multicluster.md) |

## Repository layout

Every component folder has a `README.md` (what/why/how), an `install.sh`
(Helm or kubectl, versions from [`versions.env`](versions.env)), a
`values.yaml` where relevant, and the manifests you apply.

```
versions.env                  pinned versions for every chart/manifest
scripts/                      install-all.sh, verify.sh, check-latest-versions.sh
kind/                         laptop lab: kind + Cilium + fake GPUs + vLLM simulator
platform/
  00-cilium/                  CNI, kube-proxy replacement, LB-IPAM, Hubble, netpol
  01-namespaces/              workload namespaces + Pod Security Admission
  02-metallb/                 (optional) LB IPs if not using Cilium LB-IPAM
  03-cert-manager/            certs + lab CA
  04-storage/                 NFS RWX storage class for model cache/checkpoints
  05-gpu-operator/            NVIDIA GPU Operator, time-slicing, MIG, smoke test
  06-monitoring/              kube-prometheus-stack + vLLM/DCGM/Envoy scraping
  07-keda/                    event-driven autoscaling
  08-lws/                     LeaderWorkerSet (multi-node model replicas)
  09-kueue/                   GPU quotas, queues, cohorts, priorities
security/
  01-identity-keycloak/       OIDC + gateway JWT policy
  02-secrets-openbao-eso/     OpenBao + External Secrets Operator
  03-policy-kyverno/          admission policies (audit → enforce)
  04-runtime-falco/           runtime detection, GPU-specific rules
  05-vuln-trivy/              CVE / misconfig / SBOM scanning
  06-ai-guardrails/           Llama Guard served by vLLM
gateway/
  01-envoy-gateway/           Gateway API data plane (with AI Gateway hooks)
  02-envoy-ai-gateway/        AI gateway controller + CRDs
  03-ai-routes/               Gateway, backends, model routes, auth, token budgets
  04-inference-extension/     InferencePool + Endpoint Picker (advanced routing)
inference/
  01-model-storage/           HF token, shared model cache PVC, pre-download job
  02-vllm-basic/              one vLLM Deployment by hand (learn the knobs)
  03-lmcache/                 LMCache tiers + shared KV server
  04-production-stack/        vLLM production-stack Helm (router + engines + LMCache)
  05-model-catalog/           embeddings, reranker, VLM, MoE, 70B TP, 405B LWS, LoRA, Ray Serve
  06-autoscaling/             KEDA ScaledObjects on vLLM metrics
training/
  01-object-storage/          MinIO (S3) for datasets/checkpoints/adapters
  02-mlflow/                  experiment tracking
  03-kubeflow-trainer/        TrainJob / ClusterTrainingRuntime
  04-kuberay/                 KubeRay operator + dev RayCluster
  05-jobs/                    DDP, LoRA SFT→serve, Ray Train, Ray batch inference
evaluation/
  01-load-test/               vllm bench serve jobs
  02-lm-eval/                 lm-evaluation-harness through the gateway
  03-slo-sweep/               GuideLLM sweeps → capacity table
inference/ (advanced)
  07-llm-d/                   llm-d guides + prefill/decode disaggregation sketch
  08-sglang/                  SGLang engine, A/B vs vLLM behind the gateway
lifecycle/                    BUILD YOUR OWN MODEL
  01-data-prep/               Ray Data: stream, dedup, filter, tokenize → S3
  02-pretrain/                ~124M GPT with FSDP2, DCP checkpoints, MFU
  03-sft/                     SFT with assistant-only loss masking
  04-rl-grpo/                 veRL GRPO on GSM8K with vLLM rollouts (KubeRay)
  05-eval-and-promote/        candidate deploy, lm-eval gate, promote/canary/rollback
gitops/
  01-argocd/                  Argo CD
  02-app-of-apps/             every component as an Application (sync waves), ApplicationSet
pipelines/
  01-argo-workflows/          Argo Workflows + RBAC
  02-model-release-pipeline/  data → train → register → eval → gate → promote DAG, nightly evals
observability/
  01-dashboards/              Grafana dashboards: serving, GPU fleet, scheduling
  02-alerts/                  PrometheusRules incl. TTFT SLO burn-rate alerts
  03-tracing/                 OTel Collector + Tempo, vLLM/Envoy tracing
  04-logs/                    Loki + Alloy (prompt-safe)
  05-cost/                    OpenCost, cost per 1M tokens
reliability/
  01-chaos-mesh/              Chaos Mesh
  02-experiments/             game-day experiments (incl. kind simulator set)
  03-gpu-health/              node-problem-detector, XID remediator, DCGM diag
tenancy/
  01-onboard-tenant/          namespace + quota + Kueue + netpol + RBAC + token budget
apps/
  01-open-webui/              chat UI for lab users
  02-vector-db/               Qdrant
  03-rag-app/                 FastAPI RAG over the lab docs (embed → search → rerank → chat)
  04-agent-mcp/               tool-calling agent + MCP server (k8s, Prometheus, docs)
  05-batch-api/               OpenAI-format batch via vllm run-batch (Kueue)
workbench/
  01-jupyterhub/              notebooks with GPU and Ray-client profiles
ops/
  01-backup-velero/           backups to MinIO, restore drill
  02-image-prepull/           pre-pull huge images on GPU nodes
  03-upgrades/                upgrade runbook
multicluster/
  01-multikueue-kind/         MultiKueue manager + worker on kind
.github/workflows/            lint (shellcheck, yamllint, kubeconform) + kind e2e
```

## Quick start

```bash
# Laptop (no GPUs): the whole control plane with simulated GPUs/models
cd kind && ./up.sh && ./test.sh

# GPU lab (after reading docs/03 and docs/04)
API_SERVER_IP=10.0.0.10 NFS_SERVER=10.0.0.5 NFS_PATH=/export/k8s \
  ./scripts/install-all.sh platform
./scripts/install-all.sh security
./scripts/install-all.sh gateway
kubectl -n llm-serving create secret generic hf-token --from-literal=token=hf_xxx
./scripts/install-all.sh inference
./scripts/install-all.sh training
./scripts/verify.sh
./scripts/lint.sh                 # shellcheck + yamllint + kubeconform (same as CI)
```

## A note on versions & accuracy

The AI-infra ecosystem moves monthly. Versions in `versions.env` are a
**known-compatible baseline**, not the latest. Several APIs here are still
alpha (`AIGatewayRoute`, `InferenceObjective`, `TrainJob`, Kueue v1beta1)
and change shape between releases. Each README calls out the fragile spots;
`./scripts/check-latest-versions.sh` shows what moved; `kubectl explain`
and `helm show values` are the source of truth for your installed version.
