# 02 — Pretraining a ~125M GPT from scratch (FSDP2)

`pretrain.py` is a self-contained, nanoGPT-style trainer (GPT-2-small shape:
12 layers, 768 dim, 12 heads, 1024 context, ~124M params) that uses the same
building blocks as production pretraining stacks:

| Concept | In `pretrain.py` | In torchtitan / Megatron at scale |
|---|---|---|
| Sharding | **FSDP2** `fully_shard` per block + root, bf16 params, fp32 reduce | FSDP2 + TP + PP + CP (4D), float8 |
| Launcher | `torchrun` via Kubeflow TrainJob (`PET_*` env) | same, or Slurm/JobSet |
| Data | random windows from uint16 token shards (stage 01) | deterministic, resumable, mixture-weighted loaders |
| LR schedule | linear warmup + cosine decay | WSD / cosine, tuned via scaling-law sweeps |
| Checkpoint | **DCP** (`torch.distributed.checkpoint`) sharded save → S3, auto-resume | async DCP to parallel FS, in-memory replicas |
| Telemetry | loss, tokens/s, **MFU** → MLflow | + per-rank step time, straggler detection, goodput |
| Export | full state dict → HF `GPT2LMHeadModel` safetensors → `s3://models` | conversion to the serving format |

**MFU** (model FLOPs utilisation) = achieved FLOPs ÷ peak hardware FLOPs.
FLOPs/token ≈ 6·N + 12·L·d·T. A small model on one GPU typically reaches
20–40%; well-tuned large runs hit 40–55%. Set `PEAK_TFLOPS` for your GPU (bf16
dense): A100 312, H100 SXM 989, L40S 362, RTX 4090 165.

**Resume**: every `CKPT_EVERY` steps each rank writes its DCP shard and
uploads it to `s3://checkpoints/pretrain/<RUN_NAME>/step_N/`, then rank 0
updates `latest.json`. Re-running with the same `RUN_NAME` resumes from the
latest step. Kill a pod mid-run to practise this.

### torchtitan mapping

torchtitan replaces this script with a TOML config: `[model] name=llama3
flavor=debugmodel`, `[training] batch_size/seq_len/steps`, `[parallelism]
data_parallel_shard_degree/tensor_parallel_degree`, and `[checkpoint]
enable_checkpoint folder interval`. Its config keys change between releases,
so this repo uses the self-contained script and treats torchtitan as the next
step. Swap the TrainJob command for `torchrun -m torchtitan.train
--job.config_file ...` once you pin a torchtitan version.

```bash
./run.sh                                      # 1 node × 1 GPU, 2000 steps
NUM_NODES=2 GPUS_PER_NODE=4 MAX_STEPS=5000 RUN_NAME=gpt125m-r2 ./run.sh
kubectl -n training get trainjob,workloads
kubectl -n training logs -f -l trainer.kubeflow.org/trainjob-name=pretrain-gpt125m --max-log-requests 8
```

Effective batch = `MICRO_BS × 1024 × GRAD_ACCUM × world_size` tokens per step
(16 × 1024 × 4 × 1 ≈ 65k on one GPU; raise `GRAD_ACCUM` to approach GPT-2's
~0.5M).
