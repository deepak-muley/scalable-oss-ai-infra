# vLLM production-stack — multi-model serving with router + LMCache

[vllm-project/production-stack](https://github.com/vllm-project/production-stack)
is the official reference Helm chart for running vLLM at cluster scale:

* **Serving engines**: one Deployment per model in `servingEngineSpec.modelSpec`.
* **Router** (`vllm-router-service`): OpenAI-compatible; discovers engines via
  K8s labels, routes by `model`, then by `routingLogic`:
  * `roundrobin` – baseline
  * `session` – sticky per `sessionKey` header (multi-turn chats keep their KV)
  * `prefixaware` – sends requests with a shared prefix to the same engine
  * `kvaware` – asks LMCache's controller which engine actually holds the KV
  * `disaggregated_prefill` – prefill pods → decode pods (advanced)
* **LMCache** per engine (`lmcacheConfig`) + optional shared **cache server**.
* Observability dashboards in the upstream repo (`observability/`).

The Envoy AI Gateway (gateway/03) sits *in front* of this router: gateway =
auth, quotas, provider fan-out; stack router = engine-level KV-aware routing.

| Values file | GPUs | Models |
|---|---|---|
| `values-1gpu.yaml` | 1 × ≥8 GB | Qwen2.5-1.5B-Instruct (+ LMCache CPU offload) |
| `values-multi-model.yaml` | 3 × ≥24 GB | Llama-3.1-8B chat (×2 replicas), BGE-M3 embeddings, Qwen2.5-1.5B |
| `values-shared-kv.yaml` | overlay | adds a shared LMCache cache server + kvaware routing |

```bash
kubectl -n llm-serving create secret generic hf-token --from-literal=token=hf_xxx
VALUES=values-1gpu.yaml ./install.sh
kubectl -n llm-serving get pods -w
kubectl -n llm-serving port-forward svc/vllm-router-service 30080:80
curl localhost:30080/v1/models
```

Find the engine Deployment names (needed for KEDA in 06-autoscaling):
`kubectl -n llm-serving get deploy -l ai.lab/inference-engine=vllm`

> The chart's values schema evolves; `helm show values vllm/vllm-stack` is the
> source of truth for your chart version.
