# LMCache — KV cache beyond GPU memory, shared across replicas

vLLM's prefix cache lives in **GPU HBM** and is evicted quickly under load,
and it is private to one pod. [LMCache](https://github.com/LMCache/LMCache)
plugs into vLLM via the KV-connector API (`LMCacheConnectorV1`) and adds
tiers:

```
 GPU HBM (vLLM paged KV)  ->  CPU DRAM (local_cpu)  ->  local NVMe (local_disk)
                          ->  remote shared store (LMCache server / Redis/Valkey / Mooncake / S3...)
```

Effects:
* Long shared contexts (system prompts, RAG docs, multi-turn chats, agent
  traces) skip prefill → much lower **TTFT** and less GPU spent on prefill.
* A **remote** tier lets replica B reuse KV computed by replica A, so
  scaling out doesn't throw away cache.
* Building block for **disaggregated prefill/decode** (prefill pods ship KV
  to decode pods via LMCache/NIXL).

Files:

| File | |
|---|---|
| `lmcache-server.yaml` | shared remote KV store (LMCache server, `lm://` protocol) |
| `valkey-kv-store.yaml` | alternative remote store using Valkey/Redis (`redis://`) |
| `lmcache-config.yaml` | ConfigMap with tier sizes; mounted via `LMCACHE_CONFIG_FILE` |
| `vllm-qwen-7b-lmcache.yaml` | replaces `02-vllm-basic` with an LMCache-enabled deployment (2 replicas) |

```bash
kubectl apply -f lmcache-server.yaml -f lmcache-config.yaml
kubectl apply -f vllm-qwen-7b-lmcache.yaml
kubectl -n llm-serving logs deploy/vllm-qwen-7b | grep -i lmcache
```

Experiment: send the same 8k-token document twice to *different* replicas
(port-forward each pod) and compare TTFT; then turn `remote_url` off and
repeat. That is the whole value proposition, measured.

> LMCache moves fast — config keys and the server entrypoint name have
> changed between releases. If the server pod crash-loops, check
> `docs.lmcache.ai` for the current command (`lmcache_server` vs older names).
