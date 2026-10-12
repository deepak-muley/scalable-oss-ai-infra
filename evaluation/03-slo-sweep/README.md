# SLO sweep — how many replicas does peak traffic need?

[`01-load-test`](../01-load-test/README.md) tells you how fast one setup is
at one concurrency. Capacity planning asks a different question: how many
replicas and GPUs does it take to serve peak traffic while latency stays
inside the SLO? This folder sweeps the request rate against **one**
replica, finds the highest rate that still meets the SLO, and turns that
into a replica and GPU count.

The method, and how it connects to tenant quotas, is written up in
[docs/18](../../docs/18-capacity-planning-and-tenancy.md). The numbers in
`sample-results.csv` and `capacity-worksheet.md` are illustrative. Real
capacity depends on GPU, engine, quantization, and the prompt mix, so
measure your own with `guidellm-sweep-job.yaml`.

## How a sweep works

Hold the prompt shape fixed (input length, output length, how often a
prefix repeats) and raise the offered request rate in steps. At each step
record three numbers: achieved requests per second, TTFT p95, and ITL p95.

* **SLO.** For interactive chat this lab uses TTFT p95 under 1 s and ITL
  p95 under 50 ms. Batch work has a loose latency SLO and is sized on
  throughput alone.
* **Goodput.** Requests per second that meet the SLO. Raw throughput keeps
  climbing as you push harder, and past the knee latency blows up, so
  goodput falls even while the GPU looks busy.
* **Per-replica capacity `C`.** The highest measured rate whose TTFT p95
  and ITL p95 are still inside the SLO.
* **Replicas** = ⌈ peak RPS / (C × target utilisation) ⌉. A target
  utilisation of about 0.7 leaves room for bursts and for scale-up that
  takes minutes (a cold model load is not a fast HPA tick).
* **GPUs** = replicas × GPUs per replica (the tensor-parallel size), plus
  spare replicas for a failure or a rollout. The script adds one spare by
  default.

Point the sweep at one replica's Service, not at the autoscaled router.
`C` has to be a per-replica number so you can multiply it. A sweep of the
router already includes however many replicas were up that hour, and
multiplying again double-counts them.

Match the prompt shape to production. Take the input and output lengths,
and the fraction of requests that share a prefix, from gateway token
metrics or access logs. A sweep of random 1k-token prompts will mis-size a
service whose real traffic is 8k-token RAG.

## Files

| File | Role |
|---|---|
| `guidellm-sweep-job.yaml` | in-cluster GuideLLM sweep against one model, then the analyzer |
| `analyze_capacity.py` | reads a GuideLLM JSON report or a CSV, prints `C` and the replica/GPU table |
| `sample-results.csv` | illustrative rate table so you can run the analyzer with no cluster |
| `capacity-worksheet.md` | worked example (two GPU types) and an empty template |

### `analyze_capacity.py`

The script is the part you can run on a laptop. It sorts the rows by
achieved RPS, marks each row PASS or fail against the two latency caps, and
takes `C` as the highest PASS rate.

```
replicas = ceil(peak_rps / (C * target_util))
GPUs     = (replicas + spare) * gpus_per_replica
```

`--target-util` defaults to `0.7`. `--spare-replicas` defaults to `1`.
The last line is a KEDA hint: scale out before a replica sits above about
`C × target_util` requests per second.

GuideLLM's JSON field names move between releases. The parser tries several
known paths for RPS, TTFT p95, and ITL p95. When none match, it exits and
asks you to copy the rate table into a CSV with columns
`rps,ttft_p95_ms,itl_p95_ms` and rerun with `--csv`.

### `sample-results.csv` — offline practice

These rows are made up so the arithmetic is visible. They are not a
measurement of any GPU.

| RPS | TTFT p95 (ms) | ITL p95 (ms) | Against 1000 ms / 50 ms |
|---|---|---|---|
| 0.5 → 10 | 180 → 720 | 18 → 41 | PASS |
| 12 | 1150 | 52 | fail, both caps broken |
| 14, 16 | worse | worse | fail |

So `C` is 10 req/s. At peak 40 req/s and utilisation 0.7, each replica is
planned for 7 req/s, which is ⌈40 / 7⌉ = 6 replicas, plus one spare, 7
replicas. At 1 GPU per replica that is 7 GPUs.

```bash
python3 evaluation/03-slo-sweep/analyze_capacity.py \
  --csv evaluation/03-slo-sweep/sample-results.csv \
  --ttft-p95-ms 1000 --itl-p95-ms 50 \
  --peak-rps 40 --gpus-per-replica 1
```

Tighten `--itl-p95-ms` to 30 and `C` falls, because the rows at 8 and 10
req/s no longer pass. That is the batch-size trade: a larger batch raises
throughput and stretches the gap between tokens.

### `capacity-worksheet.md`

The same formula filled in by hand for a chat API at 40 req/s, mean 1024
tokens in and 256 out, on two example GPU types (about 6 req/s per L40S,
about 11 per H100). Use the template at the bottom when you replace those
numbers with a real sweep. Also record cold-start time: it is what tells
you whether utilisation 0.7 is enough headroom for KEDA.

### `guidellm-sweep-job.yaml` — the in-cluster sweep

[GuideLLM](https://github.com/vllm-project/guidellm) steps the rate for you:
a low synchronous pass, a throughput pass, and rate steps in between
(`--rate-type sweep`). One step lasts `MAX_SECONDS` (60s here). The prompt
shape is `prompt_tokens=1024,output_tokens=256`, the same shape as the
random load test, so the two folders speak about one workload.

| Env | Default | Why |
|---|---|---|
| `TARGET` | `http://vllm-qwen-7b.llm-serving.svc.cluster.local:8000` | one replica, not the router |
| `MODEL` | `Qwen/Qwen2.5-7B-Instruct` | the name that replica serves |
| `DATA` | `prompt_tokens=1024,output_tokens=256` | match production, or the comparison is about a different workload |
| `MAX_SECONDS` | `60` | duration of each rate step |
| `TTFT_P95_MS` / `ITL_P95_MS` | `1000` / `50` | the SLO the analyzer enforces |
| `PEAK_RPS` | `40` | the traffic you are sizing for |
| `GPUS_PER_REPLICA` | `1` | tensor-parallel size of that replica |

The Job is labeled `kueue.x-k8s.io/queue-name: batch`, so it waits on the
evaluation LocalQueue like the lm-eval Job. It installs GuideLLM, writes
`/results/sweep.json`, and runs `analyze_capacity.py` from a ConfigMap.
`HF_TOKEN` is optional and only needed so GuideLLM can download a tokenizer
for the synthetic prompts. If `minio-creds` exists, the JSON is also copied
to `s3://datasets/benchmarks/` so the sweep survives the Job's log.

```bash
kubectl -n evaluation create configmap slo-analyze \
  --from-file=evaluation/03-slo-sweep/analyze_capacity.py \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f evaluation/03-slo-sweep/guidellm-sweep-job.yaml
kubectl -n evaluation logs -f job/guidellm-sweep
```

GuideLLM's CLI has moved between releases (`--rate-type` versus `--profile`,
and the `--data` syntax). The Job uses the flags that match the version
`pip install guidellm` resolves today. If the benchmark command fails on
flags, check that release's `--help` and keep the analyzer invocation as it
is: it only needs the JSON, or a CSV transcription of the same table.

After a change that should move `C` (prefix caching, FP8 KV, a different
GPU, a tighter ITL SLO), sweep again with the same `DATA` and the same
SLO. Write the new `C` into the worksheet and resize the Deployment, the
KEDA threshold, and the tenant quota from that number.
