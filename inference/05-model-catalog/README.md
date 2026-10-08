# Model catalog — one manifest per *serving pattern*

Each file is a self-contained Deployment/LWS + Service in `llm-serving`.
Pick models that fit your GPUs (see docs/07-model-catalog.md for the
memory math). Add a matching rule in `gateway/03-ai-routes/ai-gateway-route.yaml`.

| File | Pattern | Example model | GPUs |
|---|---|---|---|
| `embedding-and-reranker.yaml` | pooling models: `/v1/embeddings`, `/v1/score`/`/rerank` | bge-m3, bge-reranker-v2-m3 | 1 each, or 1 shared with time-slicing |
| `vlm-qwen-vl.yaml` | vision-language (image+text input) | Qwen2.5-VL-7B-Instruct | 1 × 24GB+ |
| `moe-expert-parallel.yaml` | Mixture-of-Experts with expert parallelism | Qwen3-30B-A3B | 2 × 48GB+ |
| `llm-tensor-parallel.yaml` | 70B dense, TP inside a node, FP8 | Llama-3.3-70B-Instruct | 4 × 80GB (or 2 × 80GB FP8) |
| `llm-multinode-lws.yaml` | model bigger than a node: TP × PP over Ray via LeaderWorkerSet | Llama-3.1-405B-Instruct-FP8 | 2 nodes × 8 GPU |
| `lora-multi-adapter.yaml` | one base model + many LoRA fine-tunes (from training/05) | Qwen2.5-0.5B + adapters | 1 |
| `rayservice-llm.yaml` | **KubeRay** RayService running Ray Serve LLM (vLLM under the hood) | Qwen2.5-1.5B | 1+ |
