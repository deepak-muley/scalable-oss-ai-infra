# SLO sweep — capacity planning from measurements

Load tests (`01-load-test`) tell you how fast one setup is. **Capacity
planning** answers a different question: *how many replicas and GPUs do I
need to serve peak traffic within my latency SLO?*

## Concepts

* **SLO**: e.g. *TTFT p95 < 1 s and ITL p95 < 50 ms* for interactive chat.
  Batch workloads have loose SLOs and are measured by throughput alone.
* **Goodput**: requests per second that **meet the SLO**. Raw throughput
  keeps climbing as you push more load, but past the knee latency explodes
  and goodput falls.
* **Per-replica capacity `C`**: the highest request rate one replica
  sustains with p95 latencies inside the SLO, found by a **sweep** that
  increases the rate until the SLO breaks.
* **Replicas needed** = ⌈ peak RPS / (C × target utilisation) ⌉. Target
  utilisation of ~0.7 leaves headroom for bursts and for slow scale-up
  (cold starts take minutes).
* **GPUs** = replicas × GPUs per replica (TP size), plus N+1 spare for
  failures and rollouts.

The answer depends on the **workload shape** (input/output token
distribution, prefix reuse), so sweep with a shape that matches production.
Measure it from gateway logs or token metrics.

## Files

| File | |
|---|---|
| `guidellm-sweep-job.yaml` | GuideLLM sweep (synchronous → throughput → rate steps in between) against a model; results to stdout and optionally `s3://datasets/benchmarks/` |
| `analyze_capacity.py` | reads GuideLLM JSON **or** a simple CSV, finds C under your SLO, prints the replica/GPU table |
| `sample-results.csv` | **illustrative, not measured** numbers so you can practice the analysis offline |
| `capacity-worksheet.md` | worked example and a template to fill in |

```bash
# offline practice
python3 analyze_capacity.py --csv sample-results.csv --ttft-p95-ms 1000 --itl-p95-ms 50 \
  --peak-rps 40 --gpus-per-replica 1

# real sweep
kubectl -n evaluation create configmap slo-analyze --from-file=analyze_capacity.py \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f guidellm-sweep-job.yaml
kubectl -n evaluation logs -f job/guidellm-sweep
```

> GuideLLM's CLI flags and JSON report schema have changed between
> releases (`--rate-type` vs `--profile`, `--data` syntax, output field
> names). The analyzer looks for fields defensively. If it can't parse your
> version's report, transcribe the rate/TTFT/ITL table into CSV and use
> `--csv`.
