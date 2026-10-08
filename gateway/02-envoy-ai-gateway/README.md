# Envoy AI Gateway — the "AI router" at the edge

[Envoy AI Gateway](https://aigateway.envoyproxy.io) adds LLM awareness on top
of Envoy Gateway:

* **Unified OpenAI-compatible API** in front of many backends (local vLLM,
  OpenAI, Anthropic, Bedrock, Vertex, Azure…), translating schemas.
* **Model-based routing** – it parses the JSON body and sets the
  `x-ai-eg-model` header, so routes can match on `"model": "..."`.
* **Model aliasing / virtualization** (`modelNameOverride`).
* **Token-aware rate limiting & usage accounting** (input/output/total
  tokens exposed as Envoy metadata → global rate limit, metrics).
* **Fallback / priority** across backends, upstream credential injection
  (`BackendSecurityPolicy`) so clients never see provider keys.
* **InferencePool** backends (Gateway API Inference Extension) for
  KV-cache/queue-aware endpoint picking.

CRDs: `AIGatewayRoute`, `AIServiceBackend`, `BackendSecurityPolicy`.

```bash
./install.sh
kubectl get pods -n envoy-ai-gateway-system
```
