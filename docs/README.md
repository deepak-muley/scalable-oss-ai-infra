# Docs index: where to start and what to read next

**Start here → [00 — Vision: a frontier lab on OSS](00-vision-frontier-lab-on-oss.md).**
It explains the whole picture (what a frontier lab runs and which OSS fills
each role), and everything else builds on it.

Alternate **reading** (📖) and **doing** (🛠). In every component folder,
read its `README.md` before running its `install.sh`; that's where most of
the "why" lives.

## Week 1 — understand the shape (laptop only)

| # | Read / do | Why |
|---|---|---|
| 1 | 📖 [00 — Vision: a frontier lab on OSS](00-vision-frontier-lab-on-oss.md) | the five systems and the OSS map |
| 2 | 📖 [01 — Architecture](01-architecture.md) | diagrams, life of a request, the two levels of routing |
| 3 | 🛠 [kind lab](../kind/README.md): `./up.sh && ./test.sh` | seeing it work makes the rest click |
| 4 | 🛠 [09 — Learning path](09-learning-path.md), Stage 0 | gateway, Kueue preemption, KEDA, Inference Extension on kind |
| 5 | 📖 [02 — OSS components](02-oss-components.md) | reference: skim, don't read cover to cover |

## Weeks 2–3 — inference on one GPU

| # | Read / do | Why |
|---|---|---|
| 6 | 📖 [05 — Inference deep dive](05-inference-deep-dive.md) | KV cache, batching, LMCache, routing: the most important doc for serving |
| 7 | 📖 [07 — Model catalog & GPU sizing](07-model-catalog.md) | the memory math |
| 8 | 📖 [03 — Hardware & cluster prereqs](03-hardware-and-cluster-prereqs.md) → 🛠 [04 — Install runbook](04-install-runbook.md) | get your GPU cluster up |
| 9 | 🛠 [09 — Learning path](09-learning-path.md), Stage 1 | vLLM knobs, prefix caching, LMCache: measure everything |

## Weeks 4–6 — training and the model lifecycle

| # | Read / do | Why |
|---|---|---|
| 10 | 📖 [06 — Training deep dive](06-training-deep-dive.md) | parallelism, Kueue, Kubeflow Trainer vs KubeRay, RL |
| 11 | 📖 [14 — Build your own model](14-build-your-own-model.md) + 🛠 [`lifecycle/`](../lifecycle/README.md) | data → pretrain → SFT → RL → ship: the core of what a lab does |
| 12 | 🛠 [09 — Learning path](09-learning-path.md), Stages 2–3 + Track A | multi-GPU and multi-node labs |

## Then — operate it like a lab (any order; [09](09-learning-path.md) Track B has exercises)

| Topic | Doc |
|---|---|
| Observability: dashboards, SLO alerts, tracing, logs, cost per token | [16 — Advanced observability](16-advanced-observability.md) (basics: [08](08-observability.md)) |
| Reliability: failure drills, chaos, GPU health | [17 — Reliability & chaos](17-reliability-and-chaos.md) |
| Capacity planning & multi-tenancy | [18 — Capacity planning & tenancy](18-capacity-planning-and-tenancy.md) |
| GitOps & model-release pipelines | [15 — GitOps & pipelines](15-gitops-and-pipelines.md) |
| Day-2 ops & multi-cluster | [21 — Day-2 ops & multicluster](21-day2-ops-and-multicluster.md) |
| Advanced serving: llm-d P/D, SGLang, speculative decoding | [19 — Advanced serving](19-advanced-serving.md) |
| Building on it: chat UI, RAG, agents + MCP, batch, notebooks | [20 — Apps & workbench](20-apps-and-workbench.md) |
| Security (read before exposing anything to others) | [12 — Security](12-security.md) |

## Finish with

| Doc | Why |
|---|---|
| [10 — Scaling to hyperscale](10-scaling-to-hyperscale.md) | the same pieces at 1000× scale |
| [11 — Decisions & FAQ](11-decisions-faq.md) | why each choice was made (Istio? llm-d? Volcano?). Read last, once you have your own opinions |

## Keep open the whole time

* [13 — Troubleshooting](13-troubleshooting.md)
* [`versions.env`](../versions.env) and `scripts/check-latest-versions.sh`, because things move fast

## All docs by number

| # | Doc | # | Doc |
|---|---|---|---|
| 00 | [Vision: frontier lab on OSS](00-vision-frontier-lab-on-oss.md) | 11 | [Decisions & FAQ](11-decisions-faq.md) |
| 01 | [Architecture](01-architecture.md) | 12 | [Security](12-security.md) |
| 02 | [OSS components](02-oss-components.md) | 13 | [Troubleshooting](13-troubleshooting.md) |
| 03 | [Hardware & cluster prereqs](03-hardware-and-cluster-prereqs.md) | 14 | [Build your own model](14-build-your-own-model.md) |
| 04 | [Install runbook](04-install-runbook.md) | 15 | [GitOps & pipelines](15-gitops-and-pipelines.md) |
| 05 | [Inference deep dive](05-inference-deep-dive.md) | 16 | [Advanced observability](16-advanced-observability.md) |
| 06 | [Training deep dive](06-training-deep-dive.md) | 17 | [Reliability & chaos](17-reliability-and-chaos.md) |
| 07 | [Model catalog & sizing](07-model-catalog.md) | 18 | [Capacity planning & tenancy](18-capacity-planning-and-tenancy.md) |
| 08 | [Observability basics](08-observability.md) | 19 | [Advanced serving](19-advanced-serving.md) |
| 09 | [Learning path (hands-on labs)](09-learning-path.md) | 20 | [Apps & workbench](20-apps-and-workbench.md) |
| 10 | [Scaling to hyperscale](10-scaling-to-hyperscale.md) | 21 | [Day-2 ops & multicluster](21-day2-ops-and-multicluster.md) |
