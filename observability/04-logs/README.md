# Logs — Loki + Grafana Alloy

* **Loki** stores logs indexed only by labels (namespace, pod, container,
  app, node) — cheap, and queried with LogQL from Grafana.
* **Grafana Alloy** (successor of Promtail / Grafana Agent) runs as a
  DaemonSet; each instance tails the pods on its own node through the
  Kubernetes API and pushes to Loki.

```bash
./install.sh
# Grafana → Explore → Loki
```

Lab storage is the pod's filesystem PVC (`loki-values.yaml`). To use MinIO
instead, switch `loki.storage.type` to `s3` (commented block in the values).

## LogQL you'll actually use

```logql
# vLLM engine errors / tracebacks
{namespace="llm-serving", container="vllm"} |~ "(?i)(error|traceback|exception)"

# CUDA OOM anywhere (serving or training)
{namespace=~"llm-serving|training"} |= "CUDA out of memory"

# NCCL timeouts / watchdog in training
{namespace="training"} |~ "NCCL (WARN|ERROR)|Watchdog caught collective operation timeout"

# Weight loading time per pod
{namespace="llm-serving"} |= "Loading weights took"

# Kubelet-level OOM kills show in events, not pod logs -> use
#   kubectl get events -A --field-selector reason=OOMKilling
# or the kube-state-metrics metric kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}

# Error rate by pod as a metric
sum by (pod) (rate({namespace="llm-serving"} |~ "(?i)error" [5m]))
```

## Privacy: never log prompts

Prompts and completions are user data. vLLM here runs with
`--disable-log-requests`; the Alloy pipeline additionally **drops any log
line that looks like a chat payload** (`"messages":` / `"prompt":`) as a
safety net. If you need prompt logs for evals/data, build a separate,
consented, access-controlled pipeline with redaction (Presidio) and
retention limits — not general-purpose logging.
