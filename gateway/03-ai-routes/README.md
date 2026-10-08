# AI routes — wiring the gateway to the models

Apply after the inference layer is up (`inference/04-production-stack`).

| File | What |
|---|---|
| `gateway.yaml` | GatewayClass + `ai-gateway` Gateway (LoadBalancer IP from Cilium LB-IPAM or MetalLB) + 50Mi body buffer (images/long prompts) |
| `backends.yaml` | Envoy `Backend` + `AIServiceBackend` objects pointing at in-cluster routers |
| `ai-gateway-route.yaml` | `AIGatewayRoute`: model name → backend, aliases, timeouts |
| `security-policy.yaml` | API-key auth for clients (`x-api-key` header) |
| `optional-token-ratelimit.yaml` | per-user token budget (needs `WITH_RATELIMIT=true` in gateway/01) |
| `optional-external-provider.yaml` | burst/fallback to an external OpenAI-compatible API |

```bash
kubectl apply -f gateway.yaml -f backends.yaml -f ai-gateway-route.yaml
kubectl apply -f security-policy.yaml      # optional but recommended

export GW=$(kubectl get gateway ai-gateway -n ai-gateway -o jsonpath='{.status.addresses[0].value}')
curl -s http://$GW/v1/models -H 'x-api-key: sk-lab-alice-change-me' | jq
curl -s http://$GW/v1/chat/completions -H 'content-type: application/json' \
  -H 'x-api-key: sk-lab-alice-change-me' \
  -d '{"model":"Qwen/Qwen2.5-1.5B-Instruct","messages":[{"role":"user","content":"hi"}]}' | jq
```

> CRD field names in Envoy AI Gateway are still `v1alpha1` and change between
> minor releases. These manifests target the version in `versions.env`; if
> `kubectl apply` complains about a field, compare with
> `kubectl explain aigatewayroute.spec --recursive`.
