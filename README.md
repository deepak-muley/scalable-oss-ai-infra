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
```

## A note on versions & accuracy

The AI-infra ecosystem moves monthly. Versions in `versions.env` are a
**known-compatible baseline**, not the latest. Several APIs here are still
alpha (`AIGatewayRoute`, `InferenceObjective`, `TrainJob`, Kueue v1beta1)
and change shape between releases. Each README calls out the fragile spots;
`./scripts/check-latest-versions.sh` shows what moved; `kubectl explain`
and `helm show values` are the source of truth for your installed version.
