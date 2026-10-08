# 13 — Troubleshooting

## Platform

| Symptom | Check | Typical cause / fix |
|---|---|---|
| Nodes `NotReady` after cluster bootstrap | `kubectl -n kube-system get pods -l k8s-app=cilium` | Cilium not installed yet, or wrong `API_SERVER_IP` (with kube-proxy removed, Cilium can't reach the API via the ClusterIP) |
| `Service type=LoadBalancer` stuck `<pending>` | `kubectl get ciliumloadbalancerippool` | pool not applied, or its range is in use; L2 policy interface regex doesn't match the NIC |
| GPU Operator pods crash-looping | `kubectl -n gpu-operator logs ds/nvidia-driver-daemonset` | driver installed on the host **and** `driver.enabled=true`; Secure Boot blocking the module; unsupported kernel |
| `nvidia.com/gpu: 0` on a node | `kubectl -n gpu-operator logs ds/nvidia-device-plugin-daemonset` | toolkit not configured in containerd, or the validator failed |
| Pod `Insufficient nvidia.com/gpu` | `kubectl describe node` | GPUs held by other pods; Kueue admitted more than the nodes have (quota above capacity) |
| Kueue job never starts | `kubectl describe workload -n training` | no LocalQueue with that name, quota too small, or flavor labels don't match nodes |

## Inference

| Symptom | Check | Typical cause / fix |
|---|---|---|
| vLLM `CUDA out of memory` at start | logs | `--gpu-memory-utilization` too high with co-tenants; `--max-model-len` too large; model too big for the GPU (docs/07) |
| `ValueError: ... max_model_len ... KV cache` | logs | lower `--max-model-len` or raise memory utilization; use FP8 KV |
| Stuck on `startupProbe` | logs | first-time weight download (watch the PVC fill up), CUDA graph capture. Raise `failureThreshold` |
| `401 / gated repo` | logs | accept the model licence on HF; `hf-token` secret missing or wrong key name `token` |
| NCCL errors with TP > 1 | logs, `/dev/shm` | `/dev/shm` too small; mount the memory-backed emptyDir (all manifests here do) |
| Gateway returns 404/`no matching route` | `kubectl get aigatewayroute -A -o yaml` status | the `model` string doesn't exactly match the rule; AIGatewayRoute not Accepted (CRD fields differ by version, so run `kubectl explain`) |
| Gateway 413 | `ClientTrafficPolicy` | raise `bufferLimit` (large prompts or base64 images) |
| Gateway 504 on long generations | `timeouts.request` in the route | raise it, and use `stream: true` |
| Envoy Gateway ignores AI routes | `kubectl -n envoy-gateway-system logs deploy/envoy-gateway` | EG not installed with the AI Gateway values file (extension manager); restart EG after the AI GW controller is up |
| LMCache not used | `kubectl logs ... | grep -i lmcache` | image without LMCache; `--kv-transfer-config` missing; config file not mounted |
| KEDA doesn't scale | `kubectl describe scaledobject`, `kubectl get hpa` | Prometheus address wrong; metric name differs in your vLLM version (query it in Prometheus first) |

## Training

| Symptom | Check | Typical cause / fix |
|---|---|---|
| torchrun hangs at rendezvous | pod logs on all ranks | not all pods scheduled (enable Kueue `waitForPodsReady`); NetworkPolicy blocking pod-to-pod in `training` |
| NCCL timeout across nodes | `NCCL_DEBUG=INFO` | wrong interface (`NCCL_SOCKET_IFNAME=eth0`); IB/RoCE misconfigured; MTU mismatch |
| RayJob stuck `Initializing` | `kubectl get raycluster`, events | image pull (Ray LLM images are large); GPU requests can't be satisfied |
| TrainJob not admitted by Kueue | `kubectl get workloads -n training` | the Kueue release lacks the `trainer.kubeflow.org/trainjob` integration, or it isn't enabled (platform/09-kueue/values.yaml) |

## kind

| Symptom | Fix |
|---|---|
| Can't reach the LB IP on macOS | expected. Use the `port-forward` in `kind/test.sh` |
| Simulator image pull fails | set `SIM_IMAGE=ghcr.io/llm-d/llm-d-inference-sim:<released tag>` |
| Fake GPUs disappeared | node restarted. Re-run `kind/fake-gpus.sh` |
| Everything slow or evicted | give Docker more RAM/CPU, or `WITH_MONITORING=false` |
