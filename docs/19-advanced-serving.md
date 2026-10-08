# 19 — Advanced serving techniques

These are the techniques that separate "it serves" from "it serves at
frontier-lab efficiency". Each section points at runnable material. Flags
are version dependent, so confirm with `vllm serve --help` for the image you
run (the repo pins `vllm/vllm-openai:v0.10.2`).

## 1. Prefill/decode disaggregation (llm-d)

**Folder:** `inference/07-llm-d`

Prefill is compute-bound and decode is memory-bandwidth-bound. In one engine
they interfere: a big prefill stalls every running decode, which shows up as
ITL spikes. Disaggregation runs them in separate pools and ships the KV
cache between them with **NIXL** (UCX, ideally over RDMA).

* **Wins:** ITL p99 under heavy long-prompt load, and independent scaling of
  the P and D pools (prompt-heavy RAG wants more P, chatty agents want
  more D).
* **Costs:** an extra hop plus KV transfer added to TTFT, a fast network
  requirement, and more moving parts (sidecar, P/D-aware scheduler).
* **Tuning knob:** the P:D ratio. Sweep it (docs/18) the same way you sweep
  replicas.

## 2. Wide expert parallelism (MoE)

MoE models (DeepSeek-V3/R1, Qwen3-MoE, Llama 4) activate only a few experts
per token. At scale:

* **Attention** runs **data-parallel** (each rank has its own batch and KV),
  and **experts** are spread over many GPUs (EP = 16, 32, 64…). Tokens are
  exchanged between them in two all-to-all phases per layer (dispatch and
  combine), using kernels like DeepEP.
* Load balancing between experts is required (redundant hot experts, EPLB).
* It needs a multi-node replica (LWS), RDMA, and usually P/D as well. This
  is the llm-d `wide-ep-lws` guide, or SGLang with `--enable-dp-attention`
  and `--ep-size`.

Single-node starting point: `inference/05-model-catalog/moe-expert-parallel.yaml`.

## 3. SGLang as a second engine

**Folder:** `inference/08-sglang`. It has the same OpenAI API, so it sits
behind the same gateway with an A/B weighted route. RadixAttention shines on
branching and multi-turn prefixes. Benchmarking both engines on *your*
workload is the only honest comparison.

## 4. Speculative decoding

Decode generates one token per forward pass, and the GPU is underused.
Speculation drafts *k* tokens cheaply, verifies them in one pass of the big
model and keeps the accepted prefix. Output is identical in distribution;
the speedup depends on the **acceptance rate**.

`--speculative-config` takes **JSON** (older vLLM used separate
`--speculative-model` / `--num-speculative-tokens` flags):

```yaml
# n-gram / prompt lookup: free, great when outputs copy from the prompt (RAG, code edits, summaries)
- --speculative-config
- '{"method":"ngram","num_speculative_tokens":5,"prompt_lookup_max":4}'

# EAGLE / EAGLE-3: small trained draft head on the target's hidden states (needs a matching draft checkpoint)
- --speculative-config
- '{"method":"eagle3","model":"yuhuili/EAGLE3-LLaMA3.1-Instruct-8B","num_speculative_tokens":3}'

# separate small draft model from the same family
- --speculative-config
- '{"model":"meta-llama/Llama-3.2-1B-Instruct","num_speculative_tokens":4}'
```

**Exercise:** add n-gram speculation to `inference/02-vllm-basic` and run
`bench-random` (random tokens: expect almost no gain) and then a
summarization-style dataset (expect gains). Check `vllm:spec_decode_*`
metrics for the acceptance rate. *Q: why does speculation help less at high
batch sizes?* (The GPU is no longer idle, so verification work competes with
real work.)

## 5. Structured outputs

Constrained decoding (via the xgrammar or guidance backends) masks invalid
tokens so outputs **always** match a JSON schema, regex or grammar. Agents
and tool calling depend on it.

```json
{"model": "lab-chat",
 "messages": [{"role": "user", "content": "Extract name and age: Ada, 36"}],
 "response_format": {"type": "json_schema", "json_schema": {"name": "person",
   "schema": {"type": "object", "properties": {"name": {"type": "string"}, "age": {"type": "integer"}},
              "required": ["name", "age"]}}}}
```

Older clients pass `extra_body={"guided_json": schema}`. Tool calling needs
`--enable-auto-tool-choice --tool-call-parser <hermes|llama3_json|...>`
matched to the model family. Reasoning models need `--reasoning-parser`.

**Exercise:** measure ITL with and without a complex schema. Then try a
schema the model "doesn't want" to follow and inspect quality. Constraints
guarantee syntax, not truth.

## 6. Long context

| Technique | Flag / where | Why |
|---|---|---|
| Chunked prefill | `--enable-chunked-prefill`, `--max-num-batched-tokens 4096–16384` | a 128k prompt is processed in chunks interleaved with decodes, which keeps ITL stable |
| FP8 KV cache | `--kv-cache-dtype fp8` | halves KV memory per token |
| KV offload/sharing | LMCache (`inference/03`) | long contexts that recur (documents, repositories) stop being re-prefilled |
| Prefix-aware routing | stack router / GIE / llm-d | sends a repeated long context to the pod that already holds it |
| Context parallelism | newer vLLM (e.g. decode context parallel options), SGLang, llm-d | splits one sequence's KV and attention across GPUs once a single GPU can't hold it; check your version's flags |
| Model limits | `--max-model-len`, RoPE scaling (`--hf-overrides` for YaRN) | don't promise context the model wasn't trained for |

**Exercise:** with `bench-shared-prefix.yaml`, raise `--random-prefix-len`
from 4k to 32k with and without LMCache. *Q: at what length does
re-prefill dominate TTFT?*

## 7. Multi-LoRA at scale

One base model serving hundreds of fine-tunes is the cheapest way to offer
per-team or per-customer models.

* vLLM: `--enable-lora --max-loras N` (GPU-resident at once),
  `--max-cpu-loras M` (CPU cache), `--max-lora-rank`. Batched kernels
  (Punica/S-LoRA style) let one batch mix adapters.
* Dynamic loading: `VLLM_ALLOW_RUNTIME_LORA_UPDATING=True` +
  `/v1/load_lora_adapter` (see `inference/05-model-catalog/lora-multi-adapter.yaml`).
  Production systems use a resolver plugin that pulls from S3 or a registry
  on demand.
* **LoRA-aware routing**: the GIE EPP prefers pods with the adapter already
  loaded and spreads popular adapters, which avoids load/evict thrash.
* The gateway maps public model names to adapters (`modelNameOverride`) and
  applies per-adapter token budgets.

**Exercise:** train two adapters with `training/05-jobs/trainjob-lora-finetune.yaml`
(change `ADAPTER_NAME` and the data), serve both and send interleaved
traffic. Compare throughput with one adapter, with two and with base only.
*Q: what's the overhead of mixing adapters in a batch?*

## 8. Putting it together: an efficiency ladder

| Step | Typical effect |
|---|---|
| prefix caching + prefix-aware routing | big TTFT and GPU savings on repeated context |
| FP8 weights + FP8 KV | more concurrency per GPU |
| right-sized `--max-num-seqs` and chunked prefill | throughput vs ITL balance |
| speculative decoding | lower ITL at low/medium load |
| LMCache tiers / shared KV | warm scale-out, long recurring contexts |
| P/D disaggregation | tail ITL at high load with long prompts |
| wide EP | makes giant MoE models economical |

Measure every step with `evaluation/01` and `evaluation/03`. Each one moves
C (docs/18), and that's the number that buys or saves GPUs.
