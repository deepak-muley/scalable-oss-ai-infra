# 07 — Model catalog and GPU sizing

## Memory math

```
weights  = params × bytes_per_param           (bf16=2, fp8=1, int4≈0.5)
kv/token = 2 × layers × kv_heads × head_dim × kv_bytes
vLLM KV budget ≈ gpu_mem × gpu_memory_utilization − weights − activations/overhead (~1–3 GB)
max concurrent tokens ≈ KV budget / kv_per_token
```

| Model | Params | Weights bf16 | KV/token bf16 | Fits on | Pattern (file) |
|---|---|---|---|---|---|
| Qwen2.5-0.5B / 1.5B-Instruct | 0.5 / 1.5 B | 1 / 3 GB | 12 / 28 KiB | any 8 GB+ GPU | `production-stack/values-1gpu.yaml`, LoRA base |
| Qwen2.5-7B / Llama-3.1-8B-Instruct | 7–8 B | 15–16 GB | 56 / 128 KiB | 1× 24 GB (short ctx), 1× 40–80 GB comfortably | `02-vllm-basic`, `values-multi-model.yaml` |
| BAAI/bge-m3 (embed), bge-reranker-v2-m3 | 0.6 B | ~1.2 GB | – | shares a GPU | `embedding-and-reranker.yaml` |
| Qwen2.5-VL-7B-Instruct | 8 B | 16 GB | + image tokens | 1× 24–48 GB | `vlm-qwen-vl.yaml` |
| Qwen3-30B-A3B (MoE, 3B active) | 30 B | 61 GB | 96 KiB | 2× 48 GB / 1× 80 GB (FP8) | `moe-expert-parallel.yaml` |
| Llama-3.3-70B-Instruct | 70 B | 140 GB | 320 KiB | 4× 80 GB (bf16) / 2× 80 GB (FP8) | `llm-tensor-parallel.yaml` |
| Llama-3.1-405B-Instruct-FP8 | 405 B | ~410 GB | 504 KiB | 2 nodes × 8× 80 GB | `llm-multinode-lws.yaml` |
| DeepSeek-V3/R1 (MoE 671B) | 671 B | ~700 GB FP8 | MLA (compressed) | 8× H200/B200 or 2 × 8× H100 | LWS + EP (llm-d "wide EP" guides) |
| Llama-Guard-3-1B | 1 B | 2 GB | – | shares a GPU | `security/06-ai-guardrails` |

Worked example: an 8B model on a 24 GB GPU at 0.90 utilisation → 21.6 −
16 − ~1.5 ≈ **4 GB of KV** ≈ 32k tokens total across all concurrent
requests. That's why `--max-model-len 32768` on a 24 GB card means about
one long request at a time. FP8 weights (8 GB) plus FP8 KV would give
roughly 6× the KV capacity.

## Choosing quantization

| Format | Quality | Speed | Hardware |
|---|---|---|---|
| bf16 | reference | baseline | all |
| FP8 (W8A8) | ≈ bf16 | faster, half the memory | Ada/Hopper/Blackwell |
| AWQ / GPTQ INT4 (W4A16) | small drop | great for memory-bound decode | all |
| FP4 / NVFP4 | promising | fastest | Blackwell |
| KV cache FP8 | tiny drop | doubles concurrency | most |

Always re-run evals (`evaluation/02-lm-eval`) after changing quantization.

## Adding a new model: checklist

1. Check its licence and gating on Hugging Face. Accept terms with the token's account.
2. Size it with the table above. Pick TP/PP/EP and the GPU type.
3. Pre-download it (`inference/01-model-storage/download-model-job.yaml`).
4. Add it to a production-stack `modelSpec`, or copy the closest catalog
   manifest.
5. Add an `AIGatewayRoute` rule (and maybe an alias).
6. Add KEDA scaling if it serves interactive traffic.
7. Benchmark (`evaluation/01`), run evals (`evaluation/02`), then promote.
