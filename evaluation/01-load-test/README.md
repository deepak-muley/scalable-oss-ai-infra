# Load testing — how fast is this serving setup?

A model change, a vLLM flag, a cache, or a router strategy is only an
improvement if latency and throughput move the way you expect. This folder
replays a controlled prompt mix against an OpenAI-compatible endpoint and
prints the latency and throughput report. Answer quality is
[`02-lm-eval`](../02-lm-eval/README.md). The highest rate that still meets a
latency SLO is [`03-slo-sweep`](../03-slo-sweep/README.md). Run a job here
before and after **one** change so the difference is attributable.

## How a benchmark run works

`vllm bench serve` ships inside the vLLM image. The Job does not start a
server. The container generates prompts and calls an endpoint that is
already up (the production-stack router by default).

For every request it records:

| Metric | What it is | What usually moves it |
|---|---|---|
| **TTFT** | time to first token: queueing plus prefill | concurrency, prefix/KV cache hits, routing |
| **TPOT / ITL** | time per output token, or the gap between streamed tokens | batch size (`--max-num-seqs`), quantization, speculative decoding |
| **E2E** | request start to last token | both of the above, plus output length |
| **Throughput** | finished requests/s and tokens/s | batch size, replicas, how close you are to the latency knee |

Read the percentiles (p50, p95, p99). A handful of queued requests dominate
the mean and hide what a typical call felt like.

The checked-in jobs use `--dataset-name=random`, so the prompts are synthetic
token sequences of a chosen length. The run is repeatable and does not
download a dataset. Two shapes are worth keeping straight:

1. **Unique prompts.** Every request is different, so nothing is reused from
   a prefix cache. This is the baseline: raw engine speed at a fixed
   concurrency.
2. **Shared prefix.** Every request starts with the same long token prefix
   and then a short unique tail. That is a long system prompt, a RAG
   document, or a chat history. Prefix caching, LMCache, and prefix-aware
   routing show up on this shape and stay invisible on the first one.

`--max-concurrency` is how many requests are in flight. Raise it when you
are looking for the knee (throughput stops rising, TTFT p95 climbs). Leave
it fixed when you are comparing two configs. `--num-prompts` is the sample
size: a few hundred shows a large effect; use more when you care about p99.

`--base-url` defaults to `vllm-router-service.llm-serving`, the
production-stack router. Point it at a single pod Service (the comment in
`bench-random.yaml` shows `vllm-qwen-7b:8000`) when you want the engine
alone. `--model` must be the name that server is already serving.

These Jobs have no Kueue queue label, so they start as soon as you apply
them. They are CPU clients. The GPUs they measure belong to the serving pods.

Keep the prompt shape, concurrency, model, and sample size the same across
the pair of runs. Store the log, or the percentiles you care about, in
MLflow or a spreadsheet so the next change has a baseline.

A finished Job keeps its name. Delete it before applying the same file
again: `kubectl -n evaluation delete job <name>`.

## Examples

### `bench-random.yaml` — unique prompts, fixed concurrency

Baseline for "how fast is this replica or router at this load?"

| Flag | Value | Why this value |
|---|---|---|
| `--backend` | `openai-chat` | chat completions, the API the gateway and the apps use |
| `--dataset-name` | `random` | synthetic tokens, no dataset download |
| `--random-input-len` | `1024` | about 1k tokens in |
| `--random-output-len` | `256` | enough decode to see ITL, short enough to finish |
| `--num-prompts` | `400` | sample size |
| `--max-concurrency` | `32` | the load knob for this run |
| `--model` | `Qwen/Qwen2.5-1.5B-Instruct` | must already be served at `--base-url` |

`HF_TOKEN` is optional. The client uses it only if it has to download a
gated tokenizer to build the random sequences. The server still needs the
model loaded.

```bash
kubectl apply -f evaluation/01-load-test/bench-random.yaml
kubectl -n evaluation logs -f job/bench-random
```

In the log, read TTFT and ITL percentiles next to request throughput. Raise
`--max-concurrency` (16, then 32, then 64) and plot throughput against TTFT
p95. The point where throughput flattens and TTFT climbs is the knee.
[`03-slo-sweep`](../03-slo-sweep/README.md) searches that knee against an
explicit SLO.

This is the job for Lab 1.1 in [docs/09](../../docs/09-learning-path.md):
change one server flag at a time (`--max-num-seqs`,
`--gpu-memory-utilization`, `--kv-cache-dtype fp8`, `--max-model-len`) and
rerun.

### `bench-shared-prefix.yaml` — one long prefix, many short tails

Measures whether repeated context is actually being reused.

| Flag | Value | Why this value |
|---|---|---|
| `--random-prefix-len` | `4000` | the repeated part: system prompt, document, or history |
| `--random-input-len` | `256` | unique tokens after the prefix |
| `--random-output-len` | `128` | short decode, so the comparison is about TTFT |
| `--num-prompts` | `300` | sample size |
| `--max-concurrency` | `16` | lower than the random job, so queueing does not hide the cache effect |

```bash
kubectl apply -f evaluation/01-load-test/bench-shared-prefix.yaml
kubectl -n evaluation logs -f job/bench-shared-prefix
```

Run it twice against the same model: once with the cache or routing change
(vLLM `--enable-prefix-caching`, LMCache, or `prefixaware` routing) and once
without. Compare **TTFT**. A hit skips prefill of those 4000 tokens, so
TTFT drops and the GPU spends its time on the 256-token tail. ITL should
stay in the same band, because decode did not change.

If TTFT stays put, the prefix is not being reused. Typical causes: caching
is off, or the router is spreading one conversation across replicas that
each hold a cold cache. See
[docs/05](../../docs/05-inference-deep-dive.md) for what prefix caching and
LMCache are doing on the server side.

### Other clients

GuideLLM, in [`03-slo-sweep`](../03-slo-sweep/README.md), steps the request
rate and reports the fastest rate whose TTFT and ITL still meet an SLO.
NVIDIA **genai-perf** produces the same family of numbers with a different
report. **k6** or **Locust** belong in front of the gateway when the
question is auth, rate limits, and HTTP behavior rather than token latency.
