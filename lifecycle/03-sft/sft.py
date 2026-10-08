"""Minimal full-parameter SFT with assistant-only loss masking (torchrun, DDP).

Env: BASE_MODEL (HF id or s3://bucket/prefix), DATA_URI (s3 jsonl with {"messages":[...]}),
     OUT_NAME, OUT_VERSION, LR, EPOCHS, MAX_LEN, MICRO_BS, GRAD_ACCUM, MAX_EXAMPLES
"""
import json, os, random
from pathlib import Path

import boto3
import torch
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP
from transformers import AutoModelForCausalLM, AutoTokenizer

E = os.environ.get
BASE_MODEL = E("BASE_MODEL", "Qwen/Qwen2.5-0.5B")
DATA_URI = E("DATA_URI", "s3://datasets/sft/ultrachat/train.jsonl")
OUT_NAME, OUT_VERSION = E("OUT_NAME", "qwen2.5-0.5b-sft"), E("OUT_VERSION", "v1")
LR, EPOCHS = float(E("LR", 1e-5)), int(E("EPOCHS", 1))
MAX_LEN, MICRO_BS, GRAD_ACCUM = int(E("MAX_LEN", 1024)), int(E("MICRO_BS", 4)), int(E("GRAD_ACCUM", 8))
MAX_EXAMPLES = int(E("MAX_EXAMPLES", 20000))

# Minimal template for models that ship without one (our toy GPT-2).
FALLBACK_TEMPLATE = (
    "{% for m in messages %}<|{{ m['role'] }}|>\n{{ m['content'] }}{{ eos_token }}\n{% endfor %}"
    "{% if add_generation_prompt %}<|assistant|>\n{% endif %}")


def s3():
    return boto3.client("s3", endpoint_url=E("AWS_ENDPOINT_URL"))


def split_uri(uri):
    b, _, k = uri[5:].partition("/")
    return b, k


def fetch_model(uri, download=True):
    if not uri.startswith("s3://"):
        return uri
    bucket, prefix = split_uri(uri.rstrip("/"))
    local = Path("/tmp/base") / prefix
    if not download:
        return str(local)
    local.mkdir(parents=True, exist_ok=True)
    pag = s3().get_paginator("list_objects_v2")
    for page in pag.paginate(Bucket=bucket, Prefix=prefix + "/"):
        for o in page.get("Contents", []):
            s3().download_file(bucket, o["Key"], str(local / Path(o["Key"]).name))
    return str(local)


def load_data(tok):
    bucket, key = split_uri(DATA_URI)
    lines = s3().get_object(Bucket=bucket, Key=key)["Body"].read().decode().splitlines()
    random.Random(0).shuffle(lines)
    examples = []
    for line in lines[:MAX_EXAMPLES]:
        msgs = json.loads(line)["messages"]
        # prompt = everything before the final assistant turn, rendered WITH the
        # generation prompt, so its tokens are an exact prefix of the full sequence
        prompt_ids = tok.apply_chat_template(msgs[:-1], tokenize=True, add_generation_prompt=True)
        full_ids = tok.apply_chat_template(msgs, tokenize=True)
        if len(full_ids) > MAX_LEN or len(prompt_ids) >= len(full_ids):
            continue
        labels = [-100] * len(prompt_ids) + full_ids[len(prompt_ids):]   # assistant-only loss
        examples.append((full_ids, labels))
    return examples


def collate(batch, pad_id):
    L = max(len(x) for x, _ in batch)
    ids = torch.full((len(batch), L), pad_id)
    lab = torch.full((len(batch), L), -100)
    att = torch.zeros((len(batch), L), dtype=torch.long)
    for i, (x, y) in enumerate(batch):
        ids[i, :len(x)], lab[i, :len(y)], att[i, :len(x)] = torch.tensor(x), torch.tensor(y), 1
    return ids.cuda(), lab.cuda(), att.cuda()


def main():
    dist.init_process_group("nccl")
    rank, world = dist.get_rank(), dist.get_world_size()
    torch.cuda.set_device(int(E("LOCAL_RANK", 0)))

    # one download per node (local rank 0), the other local ranks wait and reuse it
    path = fetch_model(BASE_MODEL, download=int(E("LOCAL_RANK", 0)) == 0)
    dist.barrier()
    tok = AutoTokenizer.from_pretrained(path)
    if tok.chat_template is None:
        tok.chat_template = FALLBACK_TEMPLATE
    if tok.pad_token_id is None:
        tok.pad_token = tok.eos_token

    model = AutoModelForCausalLM.from_pretrained(path, torch_dtype=torch.bfloat16).cuda()
    model.gradient_checkpointing_enable()
    model = DDP(model) if world > 1 else model
    opt = torch.optim.AdamW(model.parameters(), lr=LR, weight_decay=0.0)

    data = load_data(tok)
    shard = data[rank::world]
    steps_total = EPOCHS * len(shard) // (MICRO_BS * GRAD_ACCUM)
    if rank == 0:
        import mlflow
        mlflow.set_experiment("sft")
        mlflow.start_run(run_name=f"{OUT_NAME}-{OUT_VERSION}")
        mlflow.log_params(dict(base=BASE_MODEL, data=DATA_URI, examples=len(data), lr=LR,
                               epochs=EPOCHS, max_len=MAX_LEN, world=world, steps=steps_total))
        print(f"{len(data)} examples, {steps_total} optimizer steps", flush=True)

    step = 0
    model.train()
    for epoch in range(EPOCHS):
        random.Random(epoch).shuffle(shard)
        for i in range(0, len(shard) - MICRO_BS + 1, MICRO_BS):
            ids, lab, att = collate(shard[i:i + MICRO_BS], tok.pad_token_id)
            loss = model(input_ids=ids, attention_mask=att, labels=lab).loss / GRAD_ACCUM
            loss.backward()
            if (i // MICRO_BS + 1) % GRAD_ACCUM == 0:
                torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
                for g in opt.param_groups:   # linear decay
                    g["lr"] = LR * max(0.0, 1 - step / max(1, steps_total))
                opt.step(); opt.zero_grad(set_to_none=True); step += 1
                if rank == 0 and step % 10 == 0:
                    print(f"epoch {epoch} step {step}/{steps_total} loss {loss.item()*GRAD_ACCUM:.4f}", flush=True)
                    mlflow.log_metric("loss", loss.item() * GRAD_ACCUM, step=step)

    if rank == 0:
        out = Path(f"/tmp/out/{OUT_NAME}")
        (model.module if world > 1 else model).save_pretrained(out, safe_serialization=True)
        tok.save_pretrained(out)          # includes chat_template => vLLM chat works
        for f in out.iterdir():
            s3().upload_file(str(f), "models", f"{OUT_NAME}/{OUT_VERSION}/{f.name}")
        uri = f"s3://models/{OUT_NAME}/{OUT_VERSION}"
        mlflow.log_param("model_uri", uri); mlflow.end_run()
        print("uploaded", uri, flush=True)
    dist.destroy_process_group()


if __name__ == "__main__":
    main()
