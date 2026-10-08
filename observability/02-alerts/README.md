# Alerts — symptom-based, SLO-driven

Two files:

| File | Contents |
|---|---|
| `rules-gpu-and-platform.yaml` | hardware & platform: XID errors, GPU temperature, idle-but-allocated GPUs, Kueue starvation, Envoy 5xx |
| `rules-serving-slo.yaml` | serving: queue backlog, KV-cache saturation, engine down, and **multi-window multi-burn-rate** alerts on a TTFT SLO (with recording rules) |

```bash
kubectl apply -f .
kubectl -n monitoring port-forward svc/kps-prometheus 9090   # Alerts tab
```

## The TTFT SLO, explained

*SLO: 95% of requests get their first token within 2.5 s, over 30 days.*
Error budget = 5% of requests may be slower.

* `ai_lab:ttft_slow_ratio:rate<window>` = fraction of requests with TTFT > 2.5 s
  (from the histogram bucket `le="2.5"`; pick a bucket boundary that exists
  in your vLLM version's histogram).
* **burn rate** = slow ratio / 0.05. Burn rate 1 = budget used up in exactly
  30 days. The Google SRE workbook pattern:
  * **page**: burn > 14.4 over 1 h *and* over 5 m (2% of monthly budget in 1 h, still happening)
  * **ticket**: burn > 6 over 6 h *and* 30 m

Why two windows: the long window proves it's significant, the short window
proves it's *still* happening (so alerts resolve quickly after recovery).

Every alert has a `runbook_url` → docs/13-troubleshooting.md. Write your own
runbook entries as you hit real incidents; that's how real on-call works.
