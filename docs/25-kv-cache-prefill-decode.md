# 25 — KV cache, prefill, and decode

[docs/05](05-inference-deep-dive.md), [docs/19](19-advanced-serving.md), and
[docs/24](24-scaling-inference.md) use these three terms as names. This
doc is the mechanism: what a layer stores, what prefill computes, what
each decode step computes, and which latency each phase is. Sizing
numbers are in [docs/07](07-model-catalog.md). How many sequences share
a step is [docs/24](24-scaling-inference.md).

## 1. What attention keeps

Each transformer layer, for each token, produces three tensors from that
token's hidden state: a **query** (Q), a **key** (K), and a **value** (V).
The score of token *i* attending to token *j* is the dot product of Qᵢ
and Kⱼ. The layer's output for token *i* is the weighted sum of the V's
it attended to. A causal mask limits *i* to tokens at position *j* ≤ *i*.

The weight matrices that build Q, K, V, and the MLP are the model. They
are identical for every token and every request on that replica. K and V
are different for every token, and once computed for a token they stay
valid for every later token. Recomputing them would repeat the same
GEMMs. Storing them is the **KV cache**: one K and one V per layer per
token already seen.

```
kv per token = 2 × layers × kv_heads × head_dim × bytes
```

The 2 is K and V. `kv_heads` is the count of key/value heads, which
grouped-query attention makes smaller than the query-head count.
Llama-3.1-8B has 32 layers, 32 query heads, and 8 KV heads of dimension
128. In bf16 (2 bytes):

```
2 × 32 × 8 × 128 × 2 B = 128 KiB per token
```

A 32k-token conversation holds 4 GiB of cache. The same model with a KV
head per query head would be 512 KiB/token. The cache stores the 8.
Llama-3.3-70B is 320 KiB/token on the same formula, which is the row in
[docs/07](07-model-catalog.md). DeepSeek-style multi-head latent
attention stores a compressed vector instead of full K and V, so its
bytes per token sit below this formula. FP8 KV uses 1 byte instead of 2
and halves the cache.

## 2. Prefill

The prompt arrives as a whole. Token 5 of the prompt may attend to tokens
0–4, and every one of those tokens is already in the request. The engine
runs them in one forward pass (or a few, if the prompt is chunked): one
big GEMM builds Q, K, and V for every prompt position, attention runs
across the prompt, and the cache receives an entry for every layer and
every prompt token.

The logits at the last prompt position are the distribution of the
**first output token**. Sampling that token is the end of prefill. Time
to first token is queueing plus this phase.

A long prompt is **compute-bound**. The MLP and the QKᵀ matmul grow with
prompt length, and many tokens share one read of the weights, so the
GPU's ALUs stay busy. A handful of prompt tokens does not fill those
ALUs. That short step is limited by memory traffic, the same way decode
is.

Attention over a prompt of length P compares each token with every
earlier token, so the attention work grows with P². The cache write
grows with P. That is why a 100k-token prompt is a different kind of
step from a 200-token chat, and why [docs/24](24-scaling-inference.md) §3
slices it.

## 3. Decode

After the first output token, the model emits one token per step. Step
*t* has a new query for the token just chosen. It reads every cached K
and V from the prompt and from tokens already generated, appends one new
K and one new V per layer, and samples token *t+1*.

```
prompt positions  0  1  2  3
prefill           write K,V for 0..3; sample token 4
decode            read 0..3; write position 4; sample token 5
decode            read 0..4; write position 5; sample EOS
```

Each step moves two large things through GPU memory and produces one
token per sequence:

* the weights, read again because this token's GEMMs are a new pass
* the KV cache, which is longer than it was on the previous step

The arithmetic in that pass is small next to the bytes. Decode is
**memory-bandwidth-bound**. The user-visible gap between streamed tokens
is inter-token latency (ITL), also reported as time per output token
(TPOT).

An 8B model in bf16 is about 16 GB of weights. An H100 SXM moves about
3.35 TB/s from HBM. Reading those weights once takes about 5 ms, before
the cache read and kernel overhead. A single stream cannot go faster
than that bound. A batch of sequences pays the weight read once and
emits one token per sequence, which is why a wider batch raises
tokens/s and also raises each user's ITL. That tradeoff is the knee in
Lab 1.1 ([docs/09](09-learning-path.md), [docs/24](24-scaling-inference.md) §2).

The cache read catches up with the weight read only when cached tokens
get large. For this 8B model, 16 GB of cache is about 128k tokens
(16 GB / 128 KiB). A 24 GB card never holds that much cache beside the
weights. On that card the KV **budget** runs out first, while each
individual step is still dominated by the weight read. At long context
on a bigger card, the growing cache becomes a real share of the step.

A request with a 4,000-token prompt and 200 output tokens does one
prefill of 4,000 positions and 200 decode steps. Prefill sets TTFT.
Decode sets how long the stream lasts after the first token, and it is
where a busy GPU spends its time, because every concurrent stream pays
a step per output token.

## 4. Where the bytes go

| | Weights | KV cache |
|---|---|---|
| Depends on | the model | tokens so far, across every live sequence |
| During a request | stay put | one entry appended per new token, per layer |
| Freed when | the replica stops | the sequence hits EOS, its max tokens, or is preempted |
| Shared | one copy on the replica | blocks whose prefix hash matches another request |

Worked example from [docs/07](07-model-catalog.md): Llama-class 8B on a
24 GB GPU at 0.90 utilization leaves about 4 GB for cache after weights
and overhead. At 128 KiB/token that is about 32k tokens **in total**,
shared by every concurrent request. `--max-model-len 32768` on that card
admits about one long request. A second request waits, or a running one
is preempted, when the block pool is full. The log line is the one
[docs/16](16-advanced-observability.md) quotes: KV cache full.

vLLM stores the cache in fixed-size blocks, the same idea as OS pages
(PagedAttention). A short chat occupies a few blocks. It does not reserve
`--max-model-len` up front. Finished sequences return their blocks to the
pool, which is what lets a new request take a hole on the next step
([docs/24](24-scaling-inference.md) §1–2). Two requests whose prompt
prefix hashes to the same blocks point at one copy and skip prefill for
that prefix. That is prefix caching.

## 5. One engine, two profiles

A single forward pass can hold a prefill (or a chunk of one) and many
decodes. They ask for different things: the prefill wants ALUs, the
decodes want bandwidth. A 100k-token prefill in one step is a
compute-bound pause, and every decode in that step waits. ITL spikes.

Two ways this repo splits that pause:

| Technique | What changes | Where |
|---|---|---|
| Chunked prefill | the long prompt is sliced to `--max-num-batched-tokens` and mixed with live decodes in the same step | [docs/24](24-scaling-inference.md) §3, `--enable-chunked-prefill` |
| Prefill/decode disaggregation | prefill GPUs and decode GPUs are separate pools; the cache is copied across the network (NIXL, LMCache) | [docs/19](19-advanced-serving.md) §1 |

Chunked prefill keeps one replica. Disaggregation pays an extra hop so
each pool can scale on its own: prompt-heavy RAG wants more prefill
GPUs, chatty agents want more decode GPUs. The copy has to be faster
than recomputing the cache, which is why [docs/03](03-hardware-and-cluster-prereqs.md)
calls for RDMA on that path.

Speculative decoding ([docs/19](19-advanced-serving.md) §4) is still this
loop. A step may accept several drafted tokens, and each accepted token
appends its own K and V. The cache grows by the accepted prefix, and the
next step reads all of it.

## 6. What you measure

| Observation | Phase |
|---|---|
| TTFT | queue time plus prefill, including the sample of the first output token |
| ITL / TPOT | one decode step |
| `vllm:kv_cache_usage_perc` (older name `gpu_cache_usage_perc`) | fraction of the block pool in use |
| `vllm:prefix_cache_hits` | prompt tokens whose K and V were already stored, so prefill skipped them |
| preemption when the cache is full | admission ran out of blocks |

Metric names and the dashboards are [docs/08](08-observability.md). A
trace that splits queue, prefill, and decode is the span in
[docs/16](16-advanced-observability.md).
