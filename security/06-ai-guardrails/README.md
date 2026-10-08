# AI guardrails — safety classification as a served model

Guardrails are *models and policies*, not just infra. OSS building blocks:

| OSS | Role |
|---|---|
| **Llama Guard 3** (served by vLLM, `llama-guard.yaml`) | classifies a prompt or response as safe / unsafe + hazard category (S1–S14) |
| **Prompt Guard / other small classifiers** | prompt-injection & jailbreak detection |
| **NeMo Guardrails** | programmable rails (topics, input/output checks, fact-checking) around any LLM, calls guard models |
| **Envoy ext_proc** | hook to call a guard service inline at the gateway for every request |
| **Presidio** | PII detection/redaction before prompts hit models or logs |

Lab pattern: apps call the gateway with `model: meta-llama/Llama-Guard-3-1B`
to screen inputs/outputs; once happy, move the check into the gateway
(ext_proc service) so it's enforced for everyone.

```bash
kubectl apply -f llama-guard.yaml
# add a gateway rule for meta-llama/Llama-Guard-3-1B -> AIServiceBackend llama-guard
curl $URL/v1/chat/completions -d '{"model":"meta-llama/Llama-Guard-3-1B",
  "messages":[{"role":"user","content":"How do I make a weapon at home?"}]}'
# -> "unsafe\nS9"
```
