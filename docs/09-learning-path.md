# 09 — Learning path: hands-on labs

Each lab has a **goal**, **steps** and a **question to answer with data**.
Keep notes (and MLflow runs) of your measurements.

## Stage 0 — laptop (kind)

**Lab 0.1 — Gateway anatomy.** Run `kind/up.sh` and `kind/test.sh`. Trace
one request with `hubble observe -n llm-serving --protocol http`. Then read
the Envoy config: `kubectl -n envoy-gateway-system port-forward <envoy-pod>
19000` and open `localhost:19000/config_dump`. *Q: where in the config is
the model → backend mapping?*

**Lab 0.2 — Kueue economics.** Use the `kueue-demo.yaml` scenario and change
the quotas and cohort borrowing. *Q: what happens to a running low-priority
job when a high-priority one arrives? How does `reclaimWithinCohort` change
it?*

**Lab 0.3 — Autoscaling dynamics.** Run the KEDA demo on the simulator. Vary
the `threshold`, `pollingInterval` and HPA behaviour. Raise the simulator's
TTFT to 5 s to mimic cold starts. *Q: how much queueing happens before the
new replica is useful?*

**Lab 0.4 — Inference Extension.** Run `WITH_GIE=true ./up.sh`. Send
concurrent load and look at EPP logs. *Q: does the EPP send traffic away from
a pod whose queue is longer?*

## Stage 1 — one GPU

**Lab 1.1 — vLLM knobs.** Deploy `inference/02-vllm-basic`. Benchmark with
`bench-random`. Change one at a time: `--max-num-seqs` (16/64/256),
`--gpu-memory-utilization`, `--kv-cache-dtype fp8`, `--max-model-len`.
*Q: plot throughput against p95 TTFT. Where is the knee?*

**Lab 1.2 — Prefix caching.** Run `bench-shared-prefix` with
`--enable-prefix-caching` on and off. *Q: TTFT improvement as a function of
prefix length?*

**Lab 1.3 — LMCache CPU offload.** Switch to `03-lmcache` with
`max_local_cpu_size` 0 vs 20 GB, and use a workload whose shared prefixes
exceed the GPU KV. *Q: what's the hit rate per tier?*

**Lab 1.4 — LoRA loop.** Run `trainjob-lora-finetune` → MLflow →
`lora-multi-adapter` → query `model: lab-assistant`. *Q: compare answers of
the base model and the adapter. Run lm-eval on both: did general ability
regress?*

## Stage 2 — multi-GPU node

**Lab 2.1 — Multi-model stack.** Run `values-multi-model.yaml` and route
chat, embeddings and the small model through one gateway. Build a tiny RAG
client: embed, retrieve, rerank, chat.

**Lab 2.2 — Routing strategies.** Run the production stack with 2+ replicas.
Compare `roundrobin`, `session` and `prefixaware` on a multi-turn chat
benchmark. *Q: TTFT p95 and prefix hit rate per strategy?*

**Lab 2.3 — Shared KV.** `SHARED_KV=true` with `kvaware`. Scale replicas 1 →
3 mid-benchmark. *Q: do new replicas start with useful cache?*

**Lab 2.4 — TP vs DP.** On 2 GPUs, compare one TP=2 replica against two TP=1
replicas of an 8B model. *Q: which wins on throughput, and which on latency?*

**Lab 2.5 — Training vs inference contention.** Give Kueue all GPUs not used
by serving. Run `rayjob-batch-inference` (low priority) and then
`trainjob-pytorch-ddp` (high priority).

## Stage 3 — multi-node

**Lab 3.1 — NCCL.** Run `trainjob-pytorch-ddp` across 2 nodes over the Cilium
pod network, then over RDMA (Network Operator). Run `nccl-tests`
all_reduce_perf. *Q: bus bandwidth per setup?*

**Lab 3.2 — FSDP for real.** Fine-tune a 7–8B model with FSDP2 (torchtitan
or a TRL/accelerate recipe) across nodes. Measure MFU.

**Lab 3.3 — Multi-node serving.** Deploy `llm-multinode-lws.yaml` (or
DeepSeek with EP). Kill the worker pod. *Q: what does LWS do, and how long
is the outage?*

**Lab 3.4 — Disaggregation.** Follow an llm-d P/D guide on your hardware.
*Q: at what load does P/D beat aggregated serving on TPOT p99?*

## Stage 4 — think at hyperscale

Read [docs/10](10-scaling-to-hyperscale.md). For your lab, write a one-page
design for 1000× the GPUs: clusters, network, storage, scheduling, failure
handling and rollout safety. Then identify which components in this repo
survive unchanged. Most do, which is the point.
