# 08 — Observability

## Signals per layer

| Layer | Source | Key metrics / views |
|---|---|---|
| GPU | DCGM exporter (GPU Operator) | `DCGM_FI_DEV_GPU_UTIL`, `DCGM_FI_PROF_SM_ACTIVE`, `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE`, `DCGM_FI_DEV_FB_USED`, `DCGM_FI_DEV_POWER_USAGE`, `DCGM_FI_DEV_GPU_TEMP`, `DCGM_FI_DEV_XID_ERRORS`, NVLink/PCIe throughput |
| Network | Cilium / Hubble | flows, drops (policy denials!), HTTP latency per workload, DNS errors |
| Gateway | Envoy proxy stats + AI Gateway metrics | request rate/latency per route, 4xx/5xx, rate-limit rejections, **token usage per model/user** (`gen_ai.*` OpenTelemetry-style metrics) |
| Router | production-stack router `/metrics`, EPP metrics | per-engine QPS, routing decisions, cache-hit estimates |
| Engine | vLLM `/metrics` | `vllm:num_requests_running`, `vllm:num_requests_waiting`, `vllm:gpu_cache_usage_perc` / `vllm:kv_cache_usage_perc`, `vllm:prefix_cache_hits/queries`, `vllm:time_to_first_token_seconds`, `vllm:time_per_output_token_seconds` (newer: inter-token latency), `vllm:e2e_request_latency_seconds`, `vllm:prompt_tokens_total`, `vllm:generation_tokens_total`, preemptions |
| KV cache | LMCache metrics | hit rate per tier, bytes stored and retrieved |
| Scheduling | Kueue metrics | pending workloads, admission wait time, quota usage, preemptions |
| Training | MLflow, DCGM, NCCL logs | loss, tokens/s, MFU, step time breakdown |
| Ray | Ray dashboard + Prometheus | actor/task states, object store, autoscaler decisions |

## Useful PromQL

```promql
# TTFT p95 per model
histogram_quantile(0.95, sum by (le, model_name) (rate(vllm:time_to_first_token_seconds_bucket[5m])))

# generation throughput (tokens/s) per model
sum by (model_name) (rate(vllm:generation_tokens_total[1m]))

# prefix cache hit rate
sum(rate(vllm:prefix_cache_hits_total[5m])) / sum(rate(vllm:prefix_cache_queries_total[5m]))

# queue depth per pod (what KEDA scales on)
sum by (pod) (vllm:num_requests_waiting)

# GPUs allocated but idle (money on fire)
count(DCGM_FI_DEV_GPU_UTIL < 5) 

# Tensor-core activity, the honest "are we using the GPU" metric
avg by (Hostname) (DCGM_FI_PROF_PIPE_TENSOR_ACTIVE)
```

(Metric names change across vLLM versions. Run `curl pod:8000/metrics` to
see the names your version uses.)

## Dashboards

* Grafana ID **12239**: NVIDIA DCGM exporter.
* vLLM dashboards: the `examples/observability` folder in the vLLM repo and
  `observability/` in production-stack.
* Hubble UI for the service map: `kubectl -n kube-system port-forward svc/hubble-ui 12000:80`.
* Ray dashboard: `port-forward svc/<cluster>-head-svc 8265`.

## Alerts to start with

| Alert | Expression idea |
|---|---|
| GPU XID error | `increase(DCGM_FI_DEV_XID_ERRORS[5m]) > 0` → cordon the node and investigate |
| GPU too hot | `DCGM_FI_DEV_GPU_TEMP > 85` |
| Model queueing | `sum by (model_name)(vllm:num_requests_waiting) > 20 for 5m` |
| KV cache saturated | `vllm:gpu_cache_usage_perc > 0.95 for 10m` (preemptions coming) |
| TTFT SLO burn | p95 TTFT above SLO for 10m |
| Kueue starvation | pending workloads older than 1h |
| Gateway 5xx | Envoy upstream 5xx rate > 1% |

## Tracing (next step)

vLLM and Envoy can emit **OpenTelemetry** traces (vLLM
`--otlp-traces-endpoint`). Add an OTel Collector plus Tempo or Jaeger to see
a request span gateway → router → engine, including queue time, prefill and
decode. It's the fastest way to explain a slow TTFT.

## Logs

Add **Loki + Promtail/Alloy** or **OpenSearch + Fluent Bit** for log
aggregation. Never log prompt contents by default: they are user data. vLLM
uses `--disable-log-requests` here for that reason.
