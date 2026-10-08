# Cost — OpenCost + cost per token

Frontier labs live and die by **$/token** (serving) and **$/training run**.
In a lab you don't get a cloud bill, so use *amortized* prices: e.g. a GPU
bought for $25k, depreciated over 3 years ≈ $0.95/h, plus power and
hosting ≈ $1.20/GPU-hour. Put your numbers in `opencost-values.yaml`.

| Piece | Gives you |
|---|---|
| **OpenCost** (CNCF) | cost allocation per namespace/pod/label from Prometheus resource usage × prices (incl. GPUs); UI + `/allocation` API + Prometheus metrics |
| `recording-rules-cost.yaml` | `ai_lab:gpu_cost_per_hour:by_model`, `ai_lab:cost_per_1m_output_tokens:by_model`, `ai_lab:cost_per_1m_total_tokens:by_model`, per-model/tenant token usage from the AI Gateway |
| `dashboard-ai-lab-cost.yaml` | Grafana dashboard: GPU $/h by namespace & model, $ per 1M tokens, token usage by model/tenant |

```bash
./install.sh
kubectl -n opencost port-forward svc/opencost 9090:9090   # UI (chart-dependent port; see svc)
```

## How cost per token is computed

```
GPU $/h of model M  = Σ over vLLM pods serving M ( GPUs allocated to pod × node GPU $/h )
tokens/h of M       = rate(vllm:generation_tokens_total{model_name=M}[1h]) × 3600
$ per 1M out tokens = GPU $/h ÷ tokens/h × 1e6
```

Watch how it moves when you: enable FP8, raise `--max-num-seqs`, turn on
prefix caching/LMCache, scale to zero overnight. This is the number your
infra work is ultimately optimizing.

## Per-tenant usage (from the AI Gateway)

Envoy AI Gateway exports OpenTelemetry **gen_ai** metrics
(`gen_ai_client_token_usage` histogram with `gen_ai_token_type`
input/output and `gen_ai_request_model`). **Names and the endpoint that
serves them are version-dependent** — find them with:

```bash
kubectl -n envoy-gateway-system port-forward <envoy-pod> 19001
curl -s localhost:19001/stats/prometheus | grep -i gen_ai | head
```

Recent releases can add request-header labels (e.g. `x-user-id`,
`x-tenant-id`) to these metrics via an AI Gateway controller setting —
that's what turns token usage into **chargeback per tenant**.
