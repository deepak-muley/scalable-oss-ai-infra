# Chaos experiments — hypothesis first

Run each like a science experiment: **steady state → hypothesis → inject →
observe → learn → fix → re-run**. Generate steady load first
(`evaluation/01-load-test`, or `kind/test.sh` on kind) and keep the
*AI Lab — LLM Serving* dashboard open.

| # | File | Fault | Hypothesis | Observe | Likely fix |
|---|---|---|---|---|---|
| 1 | `01-kill-vllm-pod.yaml` | kill one vLLM pod (no grace) | in-flight streams on that pod fail; new requests go to survivors; replica returns in < startup time | gateway 5xx, TTFT spike, time until pod Ready, Kueue/HPA reaction | gateway retries on connect-failure (`fix-gateway-retries.yaml`), ≥2 replicas, PodDisruptionBudget, faster weight loading |
| 2 | `02-gateway-to-model-latency.yaml` | +200 ms ±50 ms between Envoy and `llm-serving` | TTFT +~200 ms, ITL unaffected *per token batch* but streaming chunks delayed | TTFT p95, burn-rate alert firing? | none needed — validate your SLO math and alert thresholds |
| 3 | `03-training-packet-loss.yaml` | 5% packet loss on training pods | NCCL slows sharply (TCP retransmits) or hits watchdog timeout | step time, `NCCL WARN` logs in Loki, job restarts | RDMA fabric, NCCL timeouts, checkpoint frequency |
| 4 | `04-kill-lws-worker.yaml` | kill a worker of the multi-node LWS model | whole group is recreated (RecreateGroupOnPodRestart); model unavailable for full reload time | downtime length, gateway behaviour | ≥2 LWS replicas, fallback route to a smaller model |
| 5 | `05-stress-cpu-on-model.yaml` | CPU+memory stress inside a vLLM pod | tokenization/scheduling (CPU) slows → TTFT & ITL up even though GPU is idle | GPU util drops while latency rises | CPU requests/limits, dedicated cores, `--api-server-count` |
| 6 | `06-kill-lmcache-server.yaml` | lose the shared KV tier | no errors (cache is an optimization) but TTFT ↑ and prefix hit rate ↓ until it refills | hit rate, TTFT, vLLM logs | that's the expected degradation; size and replicate the tier |
| 7 | `07-gameday-workflow.yaml` | 40-min serial game day: baseline → latency → kill → stress | team practices detection & response | everything | write it up (postmortem template in docs/17) |
| 8 | `08-schedule-random-vllm-kill.yaml` | kill a random vLLM pod every 30 min (cron) | continuous resilience pressure | error budget consumption | — |

`kind/` contains the same experiments aimed at the **simulator pods**
(`sim-qwen-small`, `sim-llama8b`) so you can learn the workflow on a laptop.

```bash
kubectl apply -f 01-kill-vllm-pod.yaml
kubectl get podchaos -n chaos-mesh
kubectl describe podchaos kill-one-vllm -n chaos-mesh    # events, targets
kubectl delete -f 01-kill-vllm-pod.yaml                  # stop / clean up
```
