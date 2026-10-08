# 03 — Supervised fine-tuning (SFT): turning a base model into an assistant

Pretraining teaches a model to *continue text*. SFT teaches it the
**conversation format** and assistant behaviour by training on curated
(user → assistant) dialogues. Two details matter:

1. **Chat template**: conversations are rendered into one token sequence
   with role markers (`apply_chat_template`). The same template must be used
   at serve time. vLLM reads it from `tokenizer_config.json`, which is why it's
   saved with the model.
2. **Loss masking**: only the **assistant** tokens contribute to the loss
   (labels `-100` elsewhere). Otherwise the model learns to imitate users and
   system prompts.

| Base model | Why | Expect |
|---|---|---|
| `s3://models/toy-gpt-125m/<run>` (stage 02) | learn the mechanics end to end with *your* model. A simple chat template is added, because GPT-2 has none | short, often incoherent replies. That's the point: capability comes from scale |
| `Qwen/Qwen2.5-0.5B-Instruct` / `Qwen/Qwen2.5-0.5B` | usable results on one GPU | coherent chat; measurable eval changes |

This script trains the **final assistant turn** of each conversation (simple
and correct). Production SFT trains every assistant turn, packs sequences and
mixes many datasets with tuned weights.

```bash
BASE_MODEL=Qwen/Qwen2.5-0.5B ./run.sh                               # usable track
BASE_MODEL=s3://models/toy-gpt-125m/gpt125m-r1 OUT_NAME=toy-gpt-125m-sft LR=1e-4 ./run.sh
```

Output: `s3://models/<OUT_NAME>/<OUT_VERSION>/` (HF format, safetensors +
tokenizer + chat template). Hand it to stage 05.
