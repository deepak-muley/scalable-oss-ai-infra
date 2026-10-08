# Dashboards (provisioned as code)

| Dashboard | Shows | Use it to |
|---|---|---|
| **AI Lab — LLM Serving** | QPS, TTFT p50/p95, ITL/TPOT p95, e2e p95, tokens/s, running/waiting per pod, KV-cache usage, prefix hit rate, preemptions | tune vLLM flags, compare routing strategies, verify LMCache, watch autoscaling |
| **AI Lab — GPU Fleet** | DCGM util, tensor-active, memory, power, temp, XID errors, pod→GPU map | find idle/allocated GPUs, failing hardware, thermal issues |
| **AI Lab — Scheduling** | Kueue pending/admitted/quota/wait/evictions, HPA current vs desired, GPU requests vs allocatable | understand who waits for GPUs and why |

```bash
kubectl apply -f .          # ConfigMaps labelled grafana_dashboard: "1"
kubectl -n monitoring port-forward svc/kps-grafana 3000:80   # folder "AI Lab"
```

They are **generated**: edit `gen-dashboards.py` (plain Python, no deps),
run `python3 gen-dashboards.py`, re-apply. Treat dashboards like code —
review them, version them.

Metric names drift (vLLM v0 → v1 engine, DCGM exporter, Kueue). Panels
that cover renamed metrics query both names; an empty panel usually means
the metric has a new name — check `curl <pod>:8000/metrics`.

The GPU dashboard's folder annotation needs the Grafana sidecar
`folderAnnotation: grafana_folder` setting; without it they land in "General".
