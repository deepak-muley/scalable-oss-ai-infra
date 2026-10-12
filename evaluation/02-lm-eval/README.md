# Quality evaluation — does this model still answer well?

A faster server can still be a worse model. Quantization, a LoRA adapter, a
different engine, or a chat template that drops tokens can move the answers
while latency looks better. This folder runs EleutherAI
[lm-evaluation-harness](https://github.com/EleutherAI/lm-evaluation-harness)
against a model that is already being served, through the same gateway users
call, so the API key, the route, and the model name are all on the path.

Treat a run as a gate. After a serving change that should be
quality-neutral, the score should hold. After training, compare the new
weights with the baseline on the same task and the same sample size.
Speed is [`01-load-test`](../01-load-test/README.md). Promoting a candidate
over the `lab-chat` alias, with both scores in one Job, is
[`lifecycle/05-eval-and-promote`](../../lifecycle/05-eval-and-promote/README.md).
That stage uses this same harness.

## How lm-eval works

The harness is a task runner. A **task** is a fixed set of prompts plus a
scorer. It does not load model weights. `--model local-chat-completions`
means "call an OpenAI-compatible chat endpoint and score whatever text comes
back."

For each example the harness:

1. Loads the item from the task (a question, a passage, a target answer).
2. Formats it as chat. `--apply_chat_template` uses the tokenizer's chat
   template so the prompt matches what that model family expects.
   `--fewshot_as_multiturn` puts few-shot examples in earlier turns, which
   is how a chat model was trained to see them, instead of gluing them into
   one user message.
3. POSTs it to `base_url` at a bounded concurrency (`num_concurrent`) and
   retries on failure (`max_retries`). `tokenized_requests=False` sends
   plain text and lets the server tokenize, which is what a real client does.
4. Parses the reply and scores it. The scorer depends on the task. GSM8K
   uses flexible exact match: the model may show its work, and the harness
   still looks for the final number.
5. Writes a JSON report: the metric, how many examples ran, and a standard
   error. The stderr is the reason a 200-example slice is a lab signal, and
   a release decision wants either the full set or the same slice every time.

Compare two runs when the task, `--limit`, few-shot setup, and model name
match. A drop larger than the stderr is a regression. A wiggle inside the
stderr is noise.

The Job is a normal Kubernetes Job in namespace `evaluation`. The label
`kueue.x-k8s.io/queue-name: batch` admits it through the `batch` LocalQueue
(`platform/09-kueue`), the same way a training job waits on `research`. The
container asks for CPU and memory only. GPUs stay on the serving pods; this
pod only issues HTTP calls.

Request path for the checked-in Job:

```
lm_eval  →  POST ${GATEWAY}/v1/chat/completions
             header x-api-key: ${API_KEY}
         →  Envoy AI Gateway checks the key (eval-bot)
         →  AIGatewayRoute matches the model name
         →  the backend that serves that model (production-stack router, or a single vLLM)
```

`API_KEY` is the `eval-bot` entry in
[`gateway/03-ai-routes/security-policy.yaml`](../../gateway/03-ai-routes/security-policy.yaml)
(`sk-lab-eval-change-me` until you change it). `MODEL` must be a name that
route already matches, such as `Qwen/Qwen2.5-1.5B-Instruct` or the
`lab-chat` alias. The alias is the right target when you care what users of
`lab-chat` receive. The concrete model name is the right target when you
care about that checkpoint.

Calling the gateway is the default because that is the path a client uses.
Set `GATEWAY` to a pod Service when you want the engine by itself, with no
auth and no route in the way.

Envoy names the proxy Service `envoy-ai-gateway-ai-gateway-<hash>` in
`envoy-gateway-system`. The `GATEWAY` value in the YAML is a placeholder.
Look up the real Service and edit the Job before applying:

```bash
kubectl get svc -n envoy-gateway-system
# GATEWAY=http://<that-name>.envoy-gateway-system.svc.cluster.local
```

## The example: `lm-eval-gsm8k.yaml`

[GSM8K](https://github.com/openai/grade-school-math) is grade-school math
word problems with a known numeric answer. It is the default task in this
lab because a small instruct model can score it, a math-tuned adapter should
move it, and a broken chat template drops it. It is also the default gate
in `lifecycle/05-eval-and-promote`.

| Env | Default | What to change |
|---|---|---|
| `MODEL` | `Qwen/Qwen2.5-1.5B-Instruct` | a served model name, or `lab-chat` |
| `GATEWAY` | placeholder in `ai-gateway` | the Envoy proxy Service, see above |
| `API_KEY` | `sk-lab-eval-change-me` | must match `eval-bot` in the security policy |

The container is `python:3.12-slim`. On start it installs `lm-eval[api]`
(the extra pulls in the HTTP client, not the GPU model stack), runs the
task, and prints the first 4 KB of the result JSON to stdout so
`kubectl logs` is enough. `backoffLimit: 0` means a bad key or a failed
install does not retry until the queue is full of identical failures.
`--limit 200` scores 200 of the 1,319 test problems. Use the same limit on
every run you intend to compare. Drop it for a smoke test, and raise it
when the stderr is too wide to make a decision.

```bash
kubectl apply -f evaluation/02-lm-eval/lm-eval-gsm8k.yaml
kubectl -n evaluation logs -f job/lm-eval-gsm8k
```

In the JSON, read `exact_match` (higher is better) and
`exact_match_stderr`. Record both next to the model version. A quantization
change or an adapter that drops GSM8K by more than the stderr should block
promotion. Re-run after every quantization change
([docs/07](../../docs/07-model-catalog.md)).

To score a LoRA adapter and the base model, run the Job twice with `MODEL`
set to each served name (for example `lab-assistant` and
`Qwen/Qwen2.5-1.5B-Instruct`). Same task, same limit. A math adapter should
gain on GSM8K; pair it with a general task below so the gain is not the
only number you keep.

### Other tasks

Edit `--tasks` in the Job. The harness has hundreds of tasks; these are the
ones the rest of this repo points at:

| Task | What a higher score means | Lab note |
|---|---|---|
| `gsm8k` | more grade-school problems end with the right number | the checked-in Job; default promote-gate task |
| `mmlu_pro` | more correct answers on harder multiple-choice knowledge | longer prompts, more tokens; the gateway request timeout is 600s |
| `ifeval` | the reply follows verifiable instructions (format, length, keywords) | pair with GSM8K so a math-tuned adapter cannot hide a general regression |
| `arc_challenge` | more correct science questions | small and cheap as a second check |
| `humaneval` | generated Python passes the unit tests | the scorer runs code; enable that only when you mean to |

Open-ended chat (helpfulness, multi-turn) is scored by a second model
rather than by exact match. MT-Bench, via FastChat, is the usual suite:
it sends the reply to a judge model and averages the judge's ratings.
Serve the judge from this same gateway and call it by model name, the same
way this Job calls the model under test.
