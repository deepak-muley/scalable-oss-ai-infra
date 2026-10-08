# Autoscaling vLLM with KEDA on LLM-native signals

CPU% is useless for GPU inference. Scale on what users feel:

| Signal (vLLM Prometheus metric) | Meaning | Scale out when |
|---|---|---|
| `vllm:num_requests_waiting` | requests queued, not yet scheduled | > ~5 per replica for 1 min |
| `vllm:gpu_cache_usage_perc` (newer: `vllm:kv_cache_usage_perc`) | KV-cache fullness | > 0.85 sustained |
| `vllm:time_to_first_token_seconds` (histogram) | TTFT | p95 above SLO |
| `vllm:num_requests_running` | in-flight batch | near `--max-num-seqs` |

Scale-up is **slow** (pod schedule + weights load + CUDA graphs: 30 s–10 min),
so: keep `minReplicaCount ≥ 1` for hot models, cache weights on RWX/NVMe,
use long `cooldownPeriod`s, and pre-warm before known load.

Scale-to-zero (`minReplicaCount: 0`) is great for rarely used lab models;
the first request then waits for a cold start — put a "please retry"
expectation on such models or use the gateway's fallback to another model.

```bash
kubectl apply -f scaledobject-vllm-basic.yaml
kubectl get scaledobject,hpa -n llm-serving
# generate load (evaluation/01-load-test) and watch:
kubectl get deploy -n llm-serving -w
```
