# 01 — Data preparation with Ray Data

> "Data is the model." Most of a frontier lab's pretraining effort goes into
> data: sourcing, filtering, dedup, mixture weights and decontamination
> against evals.

`prep.py` runs as a **RayJob** (CPU only) and does, at toy scale, what
pretraining data pipelines do at petabyte scale:

| Step | Here | At scale |
|---|---|---|
| Source | stream N docs of `HuggingFaceFW/fineweb-edu` (`sample-10BT`) | Common Crawl dumps, licensed data, code, books, synthetic |
| Exact dedup | SHA-1 of normalised text, keep first per hash (`groupby`) | exact + **fuzzy** dedup (MinHash-LSH), URL dedup |
| Quality filter | length, alphabetic ratio, repeated lines | classifier-based quality scores (fineweb-edu is itself a classifier-filtered set), toxicity/PII filters |
| Tokenize | GPT-2 BPE, append EOS, `uint16` token stream | trained tokenizer, packing, sequence-length bucketing |
| Shard | ~one `.bin` per Ray batch → `s3://datasets/pretrain/fineweb-edu-gpt2/` | thousands of shards with an index, mixture sampling across sources |
| Decontaminate | (exercise) | n-gram overlap removal vs every eval set |

`MODE=sft` instead converts `HuggingFaceH4/ultrachat_200k` (`train_sft`) to
chat-format JSONL at `s3://datasets/sft/ultrachat/train.jsonl` for stage 03.

```bash
./run.sh                                   # MODE=pretrain N_DOCS=100000
MODE=sft N_DOCS=20000 ./run.sh
kubectl -n training get rayjob -w
kubectl -n training logs -f job/data-prep-pretrain     # KubeRay's submitter Job has the RayJob's name
```

Rough sizing: fineweb-edu averages around 1,000 GPT-2 tokens per document,
so 100k docs ≈ 100M tokens. The Chinchilla-optimal budget for 125M params is
about 2.5B tokens (≈ 20 tokens/param), so `N_DOCS=2500000` would get you
there. That takes much longer to stream, so start small.
