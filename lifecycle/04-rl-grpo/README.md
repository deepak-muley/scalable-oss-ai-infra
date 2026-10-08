# 04 — Reinforcement learning with GRPO (veRL on KubeRay)

## Why RL after SFT

SFT imitates demonstrations. RL **optimises for an outcome**: the model
generates, a reward judges, and the policy shifts toward higher-reward
behaviour. That is how labs get reasoning, instruction-following and
safety behaviour beyond what demonstrations contain.

| Flavour | Reward comes from | Examples |
|---|---|---|
| **RLHF** | a *reward model* trained on human preference pairs | helpfulness and harmlessness tuning (PPO, DPO as an offline variant) |
| **RLAIF / Constitutional AI** | an AI judge applying written principles | Anthropic's Constitutional AI |
| **RLVR** (verifiable rewards) | a program: exact-match answer, unit tests, a proof checker | math (GSM8K/MATH), code. Here: GSM8K exact answer match |

**GRPO** (Group Relative Policy Optimization, DeepSeekMath/R1) samples *n*
answers per prompt and uses each answer's reward **relative to its group's
mean** as the advantage. No value/critic network is needed, so it's cheaper
than PPO and the standard choice for RLVR.

## The roles in one training step

```mermaid
flowchart LR
  P[(GSM8K prompts)] --> RO
  subgraph Ray cluster
    RO[Rollout: vLLM generates n=4 answers/prompt] --> RW[Reward fn: extract final number == gold?]
    RW --> ADV[GRPO advantage: r - mean(group)]
    RO --> REF[Reference policy: log-probs for KL penalty]
    ADV & REF --> ACT[Actor update: FSDP, PPO-clip loss + KL]
    ACT -->|sync new weights| RO
  end
  ACT -->|checkpoints| CK[(RWX PVC → merge → s3://models)]
```

**Why vLLM is inside the training loop:** most of each RL step is
*generation* (rollouts), and naive HF `generate` is 10–50× slower. veRL
time-shares the GPUs: vLLM generates (with KV cache, continuous batching),
then hands memory back to FSDP for the update, and gets the new weights
synced in. Your serving stack's performance knowledge applies directly here.

## Run

```bash
kubectl apply -f rl-checkpoints-pvc.yaml
./run.sh                              # 1 node × 2 GPUs, Qwen2.5-0.5B-Instruct, GSM8K
GPUS=4 MODEL=s3://models/qwen2.5-0.5b-sft/v1 ./run.sh   # start from your SFT model (needs a sync first, see notes)
kubectl -n training logs -f job/rl-grpo-gsm8k
```

Watch `val-core/openai/gsm8k/reward/mean` (validation accuracy) climb in
MLflow (experiment `rl-grpo`). For Qwen2.5-0.5B-Instruct expect roughly
0.3–0.5 at the start and noticeable gains within a few epochs.

## ⚠️ Version-sensitive

* **veRL's Hydra config keys change between releases** (`actor_rollout_ref.*`,
  `algorithm.*`, logger names, the data-preprocess script flags, and the
  checkpoint merger CLI `python -m verl.model_merger` vs the older
  `scripts/model_merger.py`). The overrides in `rayjob-grpo.yaml` follow the
  veRL GSM8K GRPO example. Diff them against
  `examples/grpo_trainer/run_qwen2-7b*.sh` **for the tag you pin**.
* Pin `VERL_IMAGE` to a published `verlai/verl` tag and `VERL_REF` to the
  matching git tag. The image must contain the same vLLM/torch versions veRL
  was tested with. Don't mix in the `rayproject` images.
* Starting from an `s3://` model: veRL wants a local path or HF id. Add a
  download step to the entrypoint (`aws s3 sync` → `/ckpt/base`) and point
  `actor_rollout_ref.model.path` there.

## Lighter alternative

For one GPU and no Ray: **TRL `GRPOTrainer`** (HF) with `use_vllm=True` runs
GRPO in a single process. It's good for understanding the algorithm, but it
doesn't teach you the distributed actor/rollout split that matters at scale.
