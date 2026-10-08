"""Minimal GPT pretraining with FSDP2 + DCP checkpoints + MLflow (torchrun).

Env knobs: N_LAYER N_HEAD N_EMBD BLOCK VOCAB MICRO_BS GRAD_ACCUM MAX_STEPS LR MIN_LR
WARMUP CKPT_EVERY EVAL_EVERY RUN_NAME DATA_BUCKET DATA_PREFIX PEAK_TFLOPS
"""
import json, math, os, shutil, time
from pathlib import Path

import boto3
import numpy as np
import torch
import torch.distributed as dist
import torch.distributed.checkpoint as dcp
import torch.nn as nn
import torch.nn.functional as F
from torch.distributed.checkpoint.state_dict import (
    StateDictOptions, get_model_state_dict, get_state_dict, set_state_dict)

try:  # public path in torch >= 2.6
    from torch.distributed.fsdp import MixedPrecisionPolicy, fully_shard
except ImportError:  # torch 2.4 / 2.5
    from torch.distributed._composable.fsdp import MixedPrecisionPolicy, fully_shard

E = os.environ.get
N_LAYER, N_HEAD, N_EMBD = int(E("N_LAYER", 12)), int(E("N_HEAD", 12)), int(E("N_EMBD", 768))
BLOCK, VOCAB = int(E("BLOCK", 1024)), int(E("VOCAB", 50304))  # 50257 padded to a multiple of 64
MICRO_BS, GRAD_ACCUM = int(E("MICRO_BS", 16)), int(E("GRAD_ACCUM", 4))
MAX_STEPS, WARMUP = int(E("MAX_STEPS", 2000)), int(E("WARMUP", 200))
LR, MIN_LR = float(E("LR", 6e-4)), float(E("MIN_LR", 6e-5))
CKPT_EVERY, EVAL_EVERY = int(E("CKPT_EVERY", 500)), int(E("EVAL_EVERY", 250))
RUN_NAME = E("RUN_NAME", "gpt125m-r1")
DATA_BUCKET, DATA_PREFIX = E("DATA_BUCKET", "datasets"), E("DATA_PREFIX", "pretrain/fineweb-edu-gpt2")
CKPT_BUCKET, MODEL_BUCKET = E("CKPT_BUCKET", "checkpoints"), E("MODEL_BUCKET", "models")
PEAK_TFLOPS = float(E("PEAK_TFLOPS", 312))


# ------------------------------------------------------------------ model (GPT-2 layout)
class Attention(nn.Module):
    def __init__(self):
        super().__init__()
        self.c_attn = nn.Linear(N_EMBD, 3 * N_EMBD)
        self.c_proj = nn.Linear(N_EMBD, N_EMBD)

    def forward(self, x):
        B, T, C = x.shape
        q, k, v = self.c_attn(x).split(C, dim=2)
        q, k, v = (t.view(B, T, N_HEAD, C // N_HEAD).transpose(1, 2) for t in (q, k, v))
        y = F.scaled_dot_product_attention(q, k, v, is_causal=True)  # flash/mem-efficient kernels
        return self.c_proj(y.transpose(1, 2).contiguous().view(B, T, C))


class MLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.c_fc = nn.Linear(N_EMBD, 4 * N_EMBD)
        self.c_proj = nn.Linear(4 * N_EMBD, N_EMBD)

    def forward(self, x):
        return self.c_proj(F.gelu(self.c_fc(x), approximate="tanh"))  # GPT-2's gelu_new


class Block(nn.Module):
    def __init__(self):
        super().__init__()
        self.ln_1, self.attn = nn.LayerNorm(N_EMBD), Attention()
        self.ln_2, self.mlp = nn.LayerNorm(N_EMBD), MLP()

    def forward(self, x):
        x = x + self.attn(self.ln_1(x))
        return x + self.mlp(self.ln_2(x))


class GPT(nn.Module):
    def __init__(self):
        super().__init__()
        self.transformer = nn.ModuleDict(dict(
            wte=nn.Embedding(VOCAB, N_EMBD), wpe=nn.Embedding(BLOCK, N_EMBD),
            h=nn.ModuleList([Block() for _ in range(N_LAYER)]), ln_f=nn.LayerNorm(N_EMBD)))
        self.lm_head = nn.Linear(N_EMBD, VOCAB, bias=False)
        self.lm_head.weight = self.transformer.wte.weight  # weight tying, as in GPT-2
        self.apply(self._init)

    @staticmethod
    def _init(m):
        if isinstance(m, (nn.Linear, nn.Embedding)):
            nn.init.normal_(m.weight, mean=0.0, std=0.02)
        if isinstance(m, nn.Linear) and m.bias is not None:
            nn.init.zeros_(m.bias)

    def forward(self, idx, targets=None):
        pos = torch.arange(idx.size(1), device=idx.device)
        x = self.transformer.wte(idx) + self.transformer.wpe(pos)
        for b in self.transformer.h:
            x = b(x)
        logits = self.lm_head(self.transformer.ln_f(x))
        loss = None if targets is None else F.cross_entropy(logits.float().view(-1, VOCAB), targets.view(-1))
        return logits, loss


# ------------------------------------------------------------------ helpers
def s3():
    return boto3.client("s3", endpoint_url=E("AWS_ENDPOINT_URL"))


def list_keys(bucket, prefix):
    keys, pag = [], s3().get_paginator("list_objects_v2")
    for page in pag.paginate(Bucket=bucket, Prefix=prefix):
        keys += [o["Key"] for o in page.get("Contents", [])]
    return keys


def load_tokens(local):
    """Every rank downloads all shards (toy scale). At real scale each rank streams
    only its slice and the loader state is checkpointed for exact resume."""
    keys = [k for k in list_keys(DATA_BUCKET, DATA_PREFIX + "/") if k.endswith(".bin")]
    if not keys:
        raise SystemExit(f"no shards at s3://{DATA_BUCKET}/{DATA_PREFIX}/ — run lifecycle/01-data-prep first")
    local.mkdir(parents=True, exist_ok=True)
    train, val = [], []
    for k in keys:
        p = local / Path(k).name
        if not p.exists():
            s3().download_file(DATA_BUCKET, k, str(p))
        (val if "/val_" in k else train).append(np.fromfile(p, dtype=np.uint16))
    train = np.concatenate(train)
    val = np.concatenate(val) if val else train[-BLOCK * 512:]
    return train, val


def get_batch(data, gen):
    ix = torch.randint(len(data) - BLOCK - 1, (MICRO_BS,), generator=gen)
    x = torch.stack([torch.from_numpy(data[i:i + BLOCK].astype(np.int64)) for i in ix])
    y = torch.stack([torch.from_numpy(data[i + 1:i + 1 + BLOCK].astype(np.int64)) for i in ix])
    return x.cuda(non_blocking=True), y.cuda(non_blocking=True)


def lr_at(step):
    if step < WARMUP:
        return LR * (step + 1) / WARMUP
    ratio = min(1.0, (step - WARMUP) / max(1, MAX_STEPS - WARMUP))
    return MIN_LR + 0.5 * (1 + math.cos(math.pi * ratio)) * (LR - MIN_LR)


def save_ckpt(model, opt, step, rank):
    # Each rank writes only ITS shard locally, then uploads; files from all ranks
    # land under one S3 prefix (DCP metadata uses relative file names).
    local = Path(f"/tmp/ckpt/rank{rank}/step_{step}")
    msd, osd = get_state_dict(model, opt)
    dcp.save({"model": msd, "optim": osd}, checkpoint_id=str(local))
    for f in local.iterdir():
        s3().upload_file(str(f), CKPT_BUCKET, f"pretrain/{RUN_NAME}/step_{step}/{f.name}")
    dist.barrier()
    if rank == 0:
        s3().put_object(Bucket=CKPT_BUCKET, Key=f"pretrain/{RUN_NAME}/latest.json",
                        Body=json.dumps({"step": step}).encode())
    shutil.rmtree(local, ignore_errors=True)


def try_resume(model, opt, rank):
    try:
        latest = json.loads(s3().get_object(Bucket=CKPT_BUCKET, Key=f"pretrain/{RUN_NAME}/latest.json")["Body"].read())
    except Exception:
        return 0
    step = latest["step"]
    local = Path(f"/tmp/resume/rank{rank}/step_{step}")
    local.mkdir(parents=True, exist_ok=True)
    for k in list_keys(CKPT_BUCKET, f"pretrain/{RUN_NAME}/step_{step}/"):
        s3().download_file(CKPT_BUCKET, k, str(local / Path(k).name))
    msd, osd = get_state_dict(model, opt)
    state = {"model": msd, "optim": osd}
    dcp.load(state, checkpoint_id=str(local))
    set_state_dict(model, opt, model_state_dict=state["model"], optim_state_dict=state["optim"])
    if rank == 0:
        print(f"resumed {RUN_NAME} from step {step}", flush=True)
    return step


def export_hf(model, rank):
    """Gather full weights and save as a HF GPT2LMHeadModel so stages 03/05 and
    vLLM can load it. nanoGPT Linear weights are transposed vs HF's Conv1D."""
    full = get_model_state_dict(model, options=StateDictOptions(full_state_dict=True, cpu_offload=True))
    if rank != 0:
        return
    from transformers import AutoTokenizer, GPT2Config, GPT2LMHeadModel
    cfg = GPT2Config(vocab_size=VOCAB, n_positions=BLOCK, n_embd=N_EMBD, n_layer=N_LAYER, n_head=N_HEAD)
    hf = GPT2LMHeadModel(cfg)
    conv1d = ("attn.c_attn.weight", "attn.c_proj.weight", "mlp.c_fc.weight", "mlp.c_proj.weight")
    sd = {k: (v.t() if k.endswith(conv1d) else v) for k, v in full.items() if k != "lm_head.weight"}
    missing, unexpected = hf.load_state_dict(sd, strict=False)
    assert not unexpected, unexpected
    assert all(m.endswith(("attn.bias", "attn.masked_bias", "lm_head.weight")) for m in missing), missing
    out = Path(f"/tmp/export/{RUN_NAME}")
    hf.save_pretrained(out, safe_serialization=True)
    AutoTokenizer.from_pretrained("gpt2").save_pretrained(out)
    for f in out.iterdir():
        s3().upload_file(str(f), MODEL_BUCKET, f"toy-gpt-125m/{RUN_NAME}/{f.name}")
    print(f"exported HF model -> s3://{MODEL_BUCKET}/toy-gpt-125m/{RUN_NAME}/", flush=True)


# ------------------------------------------------------------------ main
def main():
    dist.init_process_group("nccl")
    rank, world = dist.get_rank(), dist.get_world_size()
    torch.cuda.set_device(int(E("LOCAL_RANK", 0)))
    torch.manual_seed(1337)

    model = GPT().cuda()
    n_params = sum(p.numel() for p in model.parameters())
    mp = MixedPrecisionPolicy(param_dtype=torch.bfloat16, reduce_dtype=torch.float32)
    for blk in model.transformer.h:          # one FSDP unit per block => overlap comm/compute
        fully_shard(blk, mp_policy=mp)
    fully_shard(model, mp_policy=mp)          # root: embeddings, ln_f, tied head
    opt = torch.optim.AdamW(model.parameters(), lr=LR, betas=(0.9, 0.95), weight_decay=0.1)

    train, val = load_tokens(Path("/tmp/data"))
    start = try_resume(model, opt, rank)
    gen = torch.Generator().manual_seed(1000 * rank + start)  # different data per rank

    flops_per_token = 6 * n_params + 12 * N_LAYER * N_EMBD * BLOCK
    tokens_per_step = MICRO_BS * BLOCK * GRAD_ACCUM * world
    if rank == 0:
        import mlflow
        mlflow.set_experiment("pretrain")
        mlflow.start_run(run_name=RUN_NAME)
        mlflow.log_params(dict(params=n_params, layers=N_LAYER, d=N_EMBD, ctx=BLOCK, world=world,
                               tokens_per_step=tokens_per_step, max_steps=MAX_STEPS, lr=LR,
                               train_tokens=len(train)))
        print(f"{n_params/1e6:.1f}M params, {len(train)/1e6:.1f}M train tokens, "
              f"{tokens_per_step} tokens/step, world={world}", flush=True)

    for step in range(start, MAX_STEPS):
        t0 = time.time()
        for g in opt.param_groups:
            g["lr"] = lr_at(step)
        loss_acc = torch.zeros((), device="cuda")
        for micro in range(GRAD_ACCUM):
            model.set_requires_gradient_sync(micro == GRAD_ACCUM - 1)  # sync grads only once
            x, y = get_batch(train, gen)
            _, loss = model(x, y)
            (loss / GRAD_ACCUM).backward()
            loss_acc += loss.detach() / GRAD_ACCUM
        norm = torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        if hasattr(norm, "full_tensor"):  # FSDP2 returns a DTensor
            norm = norm.full_tensor()
        opt.step()
        opt.zero_grad(set_to_none=True)
        dist.all_reduce(loss_acc, op=dist.ReduceOp.AVG)
        torch.cuda.synchronize()
        dt = time.time() - t0
        tps = tokens_per_step / dt
        mfu = tps * flops_per_token / (world * PEAK_TFLOPS * 1e12)

        if rank == 0 and step % 10 == 0:
            print(f"step {step:5d} loss {loss_acc.item():.4f} lr {lr_at(step):.2e} "
                  f"gnorm {float(norm):.2f} {tps/1e3:.1f}k tok/s MFU {mfu*100:.1f}%", flush=True)
            mlflow.log_metrics({"loss": loss_acc.item(), "tokens_per_sec": tps, "mfu": mfu,
                                "lr": lr_at(step), "grad_norm": float(norm)}, step=step)

        if (step + 1) % EVAL_EVERY == 0:
            model.eval()
            with torch.no_grad():
                vl = torch.stack([model(*get_batch(val, gen))[1] for _ in range(20)]).mean()
            dist.all_reduce(vl, op=dist.ReduceOp.AVG)
            model.train()
            if rank == 0:
                print(f"step {step+1} val_loss {vl.item():.4f}", flush=True)
                mlflow.log_metric("val_loss", vl.item(), step=step + 1)

        if (step + 1) % CKPT_EVERY == 0 or step + 1 == MAX_STEPS:
            save_ckpt(model, opt, step + 1, rank)

    export_hf(model, rank)
    if rank == 0:
        mlflow.log_param("model_uri", f"s3://{MODEL_BUCKET}/toy-gpt-125m/{RUN_NAME}")
        mlflow.end_run()
    dist.destroy_process_group()


if __name__ == "__main__":
    main()
