# vLLM — the bare minimum, by hand

Before using Helm abstractions, deploy one vLLM server yourself so you know
what every knob does. `vllm-qwen-7b.yaml` is a Deployment + Service serving
`Qwen/Qwen2.5-7B-Instruct` on one GPU (≥24 GB) with an OpenAI-compatible API.

```bash
kubectl apply -f vllm-qwen-7b.yaml
kubectl -n llm-serving logs -f deploy/vllm-qwen-7b      # watch weights load + CUDA graphs
kubectl -n llm-serving port-forward svc/vllm-qwen-7b 8000:8000
curl localhost:8000/v1/models
curl localhost:8000/v1/chat/completions -H 'content-type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-7B-Instruct","messages":[{"role":"user","content":"Explain KV cache in 2 lines"}]}'
curl -s localhost:8000/metrics | grep -E 'vllm:(num_requests|gpu_cache_usage|kv_cache_usage)'
```

## Knobs that matter

| Flag | Meaning |
|---|---|
| `--gpu-memory-utilization 0.90` | fraction of VRAM vLLM may use; what's left after weights becomes **KV cache** |
| `--max-model-len` | max context; lowers KV reservation per sequence |
| `--max-num-seqs` | max concurrent sequences in a batch (throughput vs latency) |
| `--enable-prefix-caching` | reuse KV blocks for shared prompt prefixes (system prompts, RAG docs, multi-turn) |
| `--tensor-parallel-size N` | shard each layer across N GPUs in a node (NVLink ideal) |
| `--pipeline-parallel-size N` | split layers across N stages (often across nodes) |
| `--quantization fp8` / AWQ/GPTQ models | fit bigger models, more KV room |
| `--kv-cache-dtype fp8` | halve KV memory → ~2× concurrent tokens |
| `--enable-chunked-prefill` | interleave long prefills with decodes (smoother latency) |
| `--speculative-config` | draft-model / n-gram / EAGLE speculative decoding |
| `--enable-lora --lora-modules` | serve many fine-tunes on one base model |

`/dev/shm` must be large (memory-backed emptyDir) for tensor parallel NCCL.
