# Quality evaluation — lm-evaluation-harness against the gateway

Performance without quality is meaningless: every new model, quantization,
LoRA adapter or serving change should pass an eval gate. This Job runs
EleutherAI **lm-evaluation-harness** against the *gateway* (so it exercises
the full path, auth included) and is queued by Kueue (`batch` LocalQueue)
like any other batch workload.

```bash
kubectl apply -f lm-eval-gsm8k.yaml && kubectl -n evaluation logs -f job/lm-eval-gsm8k
```

Swap `--tasks` for `mmlu_pro`, `ifeval`, `humaneval` (needs code exec opt-in),
`arc_challenge`, etc. For agentic/chat quality use LLM-as-judge suites
(e.g. MT-Bench via FastChat, or your own evals with a judge model served
from the same gateway).
