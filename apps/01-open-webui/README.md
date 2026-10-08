# Open WebUI — a ChatGPT-style UI for the lab

[Open WebUI](https://github.com/open-webui/open-webui) is a self-hosted chat
UI that talks to any OpenAI-compatible endpoint. Here it points at the
**AI gateway**, so every UI message is authenticated, routed, rate-limited
and metered like any other client.

```bash
./install.sh
kubectl -n apps port-forward svc/open-webui 8088:80   # http://localhost:8088, first signup = admin
```

## Finding the gateway address

Envoy Gateway creates the proxy Service in `envoy-gateway-system` with a
generated name:

```bash
kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=ai-gateway,gateway.envoyproxy.io/owning-gateway-namespace=ai-gateway
# e.g. envoy-ai-gateway-ai-gateway-1a2b3c4d
```

In-cluster URL: `http://<that-name>.envoy-gateway-system.svc.cluster.local/v1`.
`install.sh` looks it up and sets it for you.

## The auth mismatch (a good lesson)

Open WebUI sends `Authorization: Bearer <key>`. Our lab gateway policy
(`gateway/03-ai-routes/security-policy.yaml`) expects `x-api-key: <key>`.
There are three ways to fix this, from best to quickest:

1. **JWT (recommended).** Switch the gateway to Keycloak JWTs
   (`security/01-identity-keycloak/gateway-jwt-policy.yaml`) and enable
   Open WebUI OIDC login (values below). Each user then gets their own
   identity end to end. Note that Open WebUI sends its *configured* API key,
   not the user's token, to the backend. For per-user metering, forward user
   info headers (`ENABLE_FORWARD_USER_INFO_HEADERS=true` → `X-OpenWebUI-User-Id`)
   and rate-limit on that header.
2. **A second Gateway listener** with its own SecurityPolicy that reads the
   API key from the `Authorization` header (Envoy Gateway `apiKeyAuth.extractFrom`
   supports headers; the stored value must then include the `Bearer ` prefix).
3. **Lab shortcut.** Point Open WebUI at the production-stack router directly
   (`http://vllm-router-service.llm-serving.svc.cluster.local/v1`). This
   bypasses auth, quotas and metering, so use it only to get going.

`install.sh` uses option 3 when `DIRECT_TO_ROUTER=true`.
