# Capacity worksheet

> **All numbers below are ILLUSTRATIVE, not measurements.** They show the
> method. Real numbers depend on GPU, engine version, quantization,
> workload shape and routing. Measure your own with `guidellm-sweep-job.yaml`.

## Worked example: Llama-3.1-8B-Instruct chat API

**Workload** (from gateway token metrics): mean 1,024 input / 256 output
tokens, 30% of requests share a 2k-token system prompt.
**SLO**: TTFT p95 ≤ 1,000 ms, ITL p95 ≤ 50 ms.
**Peak**: 40 req/s (weekday 10:00). **Growth**: +50% in 6 months.

| Step | L40S 48GB (example) | H100 80GB (example) |
|---|---|---|
| Sweep result: C (req/s within SLO) | ~6 | ~11 |
| Target utilisation | 0.7 | 0.7 |
| Planned load per replica | 4.2 | 7.7 |
| Replicas at peak = ⌈40 / planned⌉ | 10 | 6 |
| + spare (N+1) | 11 | 7 |
| GPUs (TP=1) | 11 | 7 |
| In 6 months (60 req/s) | 15 + 1 | 8 + 1 |

Then ask what changes C:

* Prefix caching or prefix-aware routing for the shared system prompt.
  **Re-sweep with the real prompt mix.** It often raises C noticeably.
* FP8 weights and KV give more KV room, larger batches and higher C, but
  rerun evals.
* A tighter ITL SLO (e.g. 30 ms) cuts C sharply, because batch size is what
  you trade against ITL.
* Cost per 1M output tokens ≈ (GPU $/h × GPUs) / (output tokens/h at
  planned load). Compare GPU types on this number, not on raw throughput.

## Template

| Field | Value |
|---|---|
| Model / engine / version | |
| GPU type, TP size | |
| Workload shape (in/out tokens, prefix share) | |
| SLO (TTFT p95, ITL p95) | |
| Measured C (req/s) | |
| Target utilisation | |
| Peak req/s (now / +6 mo) | |
| Replicas (+spare) | |
| GPUs | |
| Cold-start time (pod ready → serving) | |
| KEDA threshold derived from C | |
