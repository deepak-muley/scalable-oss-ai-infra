# Load testing — measure before you tune

`vllm bench serve` (ships in the vLLM image) replays synthetic or real
prompts against any OpenAI-compatible endpoint and reports **TTFT**, **TPOT /
ITL**, **E2E latency** percentiles, request & token **throughput**.

| Job | Purpose |
|---|---|
| `bench-random.yaml` | baseline: random 1k-in / 256-out at fixed concurrency |
| `bench-shared-prefix.yaml` | 4k-token shared prefix → shows prefix caching / LMCache / prefix-aware routing wins |

Run each twice — before and after a change (routing logic, LMCache on/off,
`--max-num-seqs`, FP8 KV, more replicas) — and compare. Keep results in
MLflow or a spreadsheet; this is how you build intuition.

```bash
kubectl apply -f bench-random.yaml && kubectl -n evaluation logs -f job/bench-random
```

Other tools: **GuideLLM** (sweeps to find max sustainable rate under an
SLO), **genai-perf** (NVIDIA), **k6/locust** for gateway-level tests.
