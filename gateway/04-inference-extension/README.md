# Gateway API Inference Extension (GIE) — "advanced path" for routing

GIE is a Kubernetes SIG project that turns any Gateway (Envoy Gateway,
kgateway, Istio, GKE) into an **inference gateway**:

* `InferencePool` (`inference.networking.k8s.io/v1`) — a set of model-server
  pods (like a Service, but for LLMs).
* **Endpoint Picker (EPP)** — an ext-proc service the proxy consults per
  request. It scrapes each vLLM pod's metrics (queue length, KV-cache
  utilisation, loaded LoRA adapters) and **picks the best pod**, with
  prefix-cache-aware scoring. This is the same scheduler core that
  **llm-d** builds on.
* `InferenceObjective` (alpha) — per-workload priority/criticality.

Compare with the production-stack router (inference/04): both do
cache-aware routing; GIE does it *inside the gateway's data path* and is the
emerging standard; the production-stack router is a separate Python
service but tightly integrated with LMCache's KV controller.

```bash
# 1) Envoy Gateway must have the inference-pool addon:
WITH_INFERENCE_POOL=true ../01-envoy-gateway/install.sh
# 2) CRDs + model server + pool + route
./install.sh
```
