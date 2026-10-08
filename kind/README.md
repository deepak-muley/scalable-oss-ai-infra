# kind lab — test the whole stack on a laptop (no GPUs)

Brings up the **same** platform/gateway/training components as the real lab,
using the real `install.sh` scripts, on a 4-node kind cluster with **Cilium**
as CNI (no kube-proxy). GPUs and models are simulated:

| Real lab | kind lab |
|---|---|
| NVIDIA GPU Operator → `nvidia.com/gpu` | `fake-gpus.sh` patches node capacity (4 fake GPUs × 2 nodes) |
| vLLM engines | [`llm-d-inference-sim`](https://github.com/llm-d/llm-d-inference-sim): OpenAI API + vLLM metrics, configurable TTFT/ITL |
| MetalLB / Cilium L2 on LAN | Cilium LB-IPAM on the kind docker network (+ port-forward on macOS) |
| RWX NFS model cache | not needed (sims have no weights) |

What you can **really** test here: Cilium + Hubble, Gateway API, Envoy AI
Gateway routing/aliases/auth/token accounting, Inference Extension EPP,
KEDA autoscaling on vLLM metrics, Kueue quotas/cohorts/preemption with GPU
requests, KubeRay jobs, Kubeflow Trainer CRDs, Prometheus/Grafana wiring.

What you can't: CUDA, NCCL, real throughput/latency, LMCache, GPU Operator.

## Requirements

* Docker (Desktop: give it **≥ 8 CPUs / 12 GB RAM**), `kind` ≥ 0.20, `kubectl`, `helm` ≥ 3.14
* Optional: `cilium` CLI, `hubble` CLI

## Use

```bash
./up.sh                         # ~10 min first time (image pulls)
./test.sh                       # PASS/FAIL checks + Kueue & KEDA demos
kubectl -n kube-system port-forward svc/hubble-ui 12000:80     # watch flows
kubectl -n monitoring port-forward svc/kps-grafana 3000:80     # admin/prom-operator
./down.sh
```

Flags: `WITH_MONITORING=false` (lighter), `WITH_SECURITY=true` (Kyverno audit + Falco + OpenBao/ESO), `WITH_GIE=true` (Inference
Extension pool of 3 sims), `WITH_TRAINER=true` (Kubeflow Trainer),
`SIM_IMAGE=ghcr.io/llm-d/llm-d-inference-sim:<tag>` to pin the simulator.

## Talk to it like the real thing

```bash
kubectl -n envoy-gateway-system port-forward svc/$(kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=ai-gateway -o jsonpath='{.items[0].metadata.name}') 8080:80 &
python - <<'PY'
from openai import OpenAI
c = OpenAI(base_url="http://localhost:8080/v1", api_key="unused",
           default_headers={"x-api-key": "sk-lab-alice-change-me"})
print(c.chat.completions.create(model="lab-chat",
      messages=[{"role": "user", "content": "hi"}]).choices[0].message.content)
PY
```
