"""Pretraining / SFT data prep with Ray Data (runs inside a KubeRay RayJob).

MODE=pretrain: stream fineweb-edu -> hash dedup -> quality filter -> GPT-2 tokenize
               -> uint16 .bin shards in s3://$BUCKET/$PREFIX/{train,val}_XXXXX.bin
MODE=sft:      ultrachat_200k (train_sft) -> chat JSONL in s3://$BUCKET/sft/ultrachat/train.jsonl
"""
import hashlib, io, json, os, re, uuid

import boto3
import numpy as np
import ray

MODE = os.environ.get("MODE", "pretrain")
N_DOCS = int(os.environ.get("N_DOCS", "100000"))
BUCKET = os.environ.get("BUCKET", "datasets")
PREFIX = os.environ.get("PREFIX", "pretrain/fineweb-edu-gpt2")
VAL_PROB = float(os.environ.get("VAL_PROB", "0.05"))  # chance a shard becomes a val shard


def s3():
    # AWS_ENDPOINT_URL / keys come from the minio-creds secret (envFrom)
    return boto3.client("s3", endpoint_url=os.environ.get("AWS_ENDPOINT_URL"))


def stream_rows(dataset, name, split, n, fields):
    """Stream the first n rows on the driver. HF streaming avoids downloading the
    whole 10B-token sample; Ray parallelises everything after this point."""
    from datasets import load_dataset
    ds = load_dataset(dataset, name=name, split=split, streaming=True)
    rows = []
    for i, r in enumerate(ds):
        if i >= n:
            break
        rows.append({k: r[k] for k in fields})
    print(f"streamed {len(rows)} rows from {dataset}", flush=True)
    return rows


# ---------------------------------------------------------------- pretrain
def add_hash_and_quality(batch):
    texts = batch["text"]
    hashes, keep = [], []
    for t in texts:
        norm = re.sub(r"\s+", " ", t.strip().lower())
        hashes.append(hashlib.sha1(norm.encode()).hexdigest())
        lines = [l for l in t.splitlines() if l.strip()]
        alpha = sum(c.isalpha() for c in t) / max(1, len(t))
        dup_line_ratio = 1 - len(set(lines)) / max(1, len(lines))
        keep.append(200 <= len(t) <= 100_000 and alpha > 0.6 and dup_line_ratio < 0.3)
    batch["hash"] = np.array(hashes)
    batch["keep"] = np.array(keep)
    return batch


class Tokenize:
    """Stateful actor-style UDF: load the tokenizer once per worker."""
    def __init__(self):
        from transformers import AutoTokenizer
        self.tok = AutoTokenizer.from_pretrained("gpt2")
        self.eos = self.tok.eos_token_id

    def __call__(self, batch):
        ids = self.tok(list(batch["text"]), add_special_tokens=False)["input_ids"]
        flat = []
        for x in ids:
            flat.extend(x)
            flat.append(self.eos)  # document boundary
        arr = np.array(flat, dtype=np.uint16)  # GPT-2 vocab (50257) fits in uint16
        split = "val" if np.random.rand() < VAL_PROB else "train"
        key = f"{PREFIX}/{split}_{uuid.uuid4().hex[:12]}.bin"
        s3().put_object(Bucket=BUCKET, Key=key, Body=arr.tobytes())
        return {"key": [key], "tokens": [len(arr)]}


def pretrain():
    rows = stream_rows("HuggingFaceFW/fineweb-edu", "sample-10BT", "train", N_DOCS, ["text"])
    ds = ray.data.from_items(rows)
    ds = ds.map_batches(add_hash_and_quality, batch_format="numpy")
    ds = ds.filter(lambda r: bool(r["keep"]))
    before = ds.count()
    # exact dedup: one row per content hash
    ds = ds.groupby("hash").map_groups(lambda g: {k: v[:1] for k, v in g.items()}, batch_format="numpy")
    after = ds.count()
    print(f"quality-kept={before} after-dedup={after} (removed {before - after} duplicates)", flush=True)
    shards = ds.map_batches(Tokenize, batch_size=2000, concurrency=4, batch_format="numpy").take_all()
    total = sum(int(s["tokens"]) for s in shards)
    n_val = sum(1 for s in shards if "/val_" in s["key"])
    if n_val == 0:
        print("WARNING: no val shard written; stage 02 will reuse a train shard for eval")
    manifest = {"shards": [s["key"] for s in shards], "tokens": total, "docs": after, "tokenizer": "gpt2"}
    s3().put_object(Bucket=BUCKET, Key=f"{PREFIX}/manifest.json", Body=json.dumps(manifest).encode())
    print(f"wrote {len(shards)} shards, {total/1e6:.1f}M tokens -> s3://{BUCKET}/{PREFIX}/", flush=True)


# ---------------------------------------------------------------- sft
def sft():
    rows = stream_rows("HuggingFaceH4/ultrachat_200k", None, "train_sft", N_DOCS, ["messages"])
    buf = io.StringIO()
    kept = 0
    for r in rows:
        msgs = [{"role": m["role"], "content": m["content"]} for m in r["messages"]]
        if len(msgs) >= 2 and msgs[-1]["role"] == "assistant":
            buf.write(json.dumps({"messages": msgs}) + "\n")
            kept += 1
    key = "sft/ultrachat/train.jsonl"
    s3().put_object(Bucket=BUCKET, Key=key, Body=buf.getvalue().encode())
    print(f"wrote {kept} conversations -> s3://{BUCKET}/{key}", flush=True)


if __name__ == "__main__":
    ray.init()
    pretrain() if MODE == "pretrain" else sft()
