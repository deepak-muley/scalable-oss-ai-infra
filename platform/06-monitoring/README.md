# Monitoring — kube-prometheus-stack + GPU & vLLM metrics

Installs Prometheus Operator, Prometheus, Alertmanager, Grafana,
node-exporter, kube-state-metrics. Then:

* **DCGM exporter** (from the GPU Operator) is scraped via its ServiceMonitor.
* **vLLM** engines are scraped by `podmonitor-vllm.yaml` (any pod labelled
  `ai.lab/inference-engine: vllm`, port 8000 `/metrics`).
* **Envoy** proxy metrics via `podmonitor-envoy.yaml`.

Prometheus is reachable in-cluster at
`http://kps-prometheus.monitoring.svc:9090` (KEDA uses this).

```bash
./install.sh
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
# admin / prom-operator  (change it in values.yaml)
```

Dashboards to import (Grafana → Dashboards → Import):

* **12239** – NVIDIA DCGM Exporter dashboard
* vLLM: `examples/observability/dashboards` in the vllm repo, or the
  production-stack `observability/` dashboard JSON.

Key metrics you will live in: see docs/08-observability.md.
