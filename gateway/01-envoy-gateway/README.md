# Envoy Gateway — the data plane for the AI gateway

[Envoy Gateway](https://gateway.envoyproxy.io) implements the Kubernetes
**Gateway API** (`GatewayClass`, `Gateway`, `HTTPRoute`) and provisions
Envoy proxy Deployments for each `Gateway`. Envoy AI Gateway (next folder)
plugs into it through Envoy Gateway's **extension manager** hook — so Envoy
Gateway must be installed with the AI Gateway's values file.

`install.sh` downloads the values files matching `AI_GATEWAY_VERSION` into
this folder (so you can read them) and installs Envoy Gateway with them.

Optional add-ons (env flags):

| Flag | Adds |
|---|---|
| `WITH_INFERENCE_POOL=true` | lets routes target a Gateway API Inference Extension `InferencePool` (gateway/04) |
| `WITH_RATELIMIT=true` | Redis-backed global rate limiting (needed for per-user **token** budgets) |

If a download 404s, the file moved upstream — browse
`https://github.com/envoyproxy/ai-gateway/tree/<version>/manifests` and
`.../examples` and fix the path in install.sh.
