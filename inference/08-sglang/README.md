# SGLang — a second inference engine behind the same gateway

[SGLang](https://github.com/sgl-project/sglang) is the main OSS alternative
to vLLM. Both expose an **OpenAI-compatible API**, so the gateway, routing,
autoscaling patterns and benchmarks in this repo work unchanged. Swapping
engines is a backend change, not a platform change.

| | vLLM | SGLang |
|---|---|---|
| KV reuse | PagedAttention + hash-based prefix caching | **RadixAttention**: a radix tree of prefixes, very strong on branching/multi-turn/agent workloads |
| Structured output | xgrammar / guidance backends | xgrammar, with a fast constrained-decoding path; a frontend DSL for multi-call programs |
| Large MoE (DeepSeek) | good, wide-EP via llm-d | very strong: DP-attention, EP, DeepEP, MLA kernels; often first with DeepSeek optimizations |
| Ecosystem here | production-stack, LMCache, GIE, Ray Serve LLM, llm-d | GIE works (it's engine-agnostic if metrics are mapped), SGLang router, Dynamo |
| Metrics | `vllm:*` | `sglang:*` (`--enable-metrics`) |

Files:

| File | |
|---|---|
| `sglang-qwen-7b.yaml` | Deployment + Service for Qwen2.5-7B-Instruct on 1 GPU |
| `podmonitor-sglang.yaml` | Prometheus scraping for `ai.lab/inference-engine: sglang` pods |
| `gateway-ab.yaml` | Backend + AIServiceBackend + AIGatewayRoute: `model: sglang/qwen-7b` → SGLang, and a weighted A/B alias `lab-chat-ab` split 50/50 between the vLLM and SGLang backends |

```bash
kubectl apply -f sglang-qwen-7b.yaml -f podmonitor-sglang.yaml
kubectl apply -f gateway-ab.yaml
kubectl -n llm-serving port-forward svc/sglang-qwen-7b 8000:8000
curl localhost:8000/v1/chat/completions -H 'content-type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-7B-Instruct","messages":[{"role":"user","content":"hi"}]}'
```

> The image tag is pinned for reproducibility; SGLang releases often, and the
> CUDA suffix must match your driver. Verify on Docker Hub
> (`lmsysorg/sglang`) and check `python3 -m sglang.launch_server --help` for
> flag names.

## Exercise: vLLM vs SGLang, same GPU, same model

`vllm bench serve --backend openai-chat` speaks plain OpenAI, so it
benchmarks SGLang too.

1. Run `evaluation/01-load-test/bench-random.yaml` against
   `http://vllm-qwen-7b.llm-serving.svc:8000` (inference/02), then against
   `http://sglang-qwen-7b.llm-serving.svc:8000`. Change `--base-url` only.
2. Repeat with `bench-shared-prefix.yaml` (shared 4k prefix).
3. Repeat with a multi-turn workload, which is RadixAttention's strength.

Record throughput, TTFT p95 and ITL p95. *Questions:* which engine wins on
which workload? How much does the difference shrink when vLLM has prefix
caching on? Was memory configuration equal (`--gpu-memory-utilization 0.90`
vs `--mem-fraction-static 0.85` are **not** the same quantity: SGLang's
covers weights plus KV pool only)?
