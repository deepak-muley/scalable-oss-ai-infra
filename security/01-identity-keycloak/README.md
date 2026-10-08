# Keycloak — OIDC identity for users, tenants and services

* Users/teams log in (SSO) and get **JWTs**; services use client-credentials.
* Envoy Gateway validates the JWT at the edge (`gateway-jwt-policy.yaml`) and
  copies claims into headers (`sub → x-user-id`, `tenant → x-tenant-id`),
  which feed **per-user token rate limits** and access logs.
* Same IdP for Grafana, MLflow, Ray dashboard, Argo (via oauth2-proxy).

Lab mode runs Keycloak `start-dev` (in-memory H2). For anything real:
Postgres + `start` + TLS hostname.

```bash
./install.sh
kubectl -n security port-forward svc/keycloak-keycloakx-http 8081:80
# http://localhost:8081  admin / admin  -> create realm "ai-lab",
#   client "ai-gateway" (confidential, service accounts on), users alice/bob,
#   a "tenant" user attribute + protocol mapper to put it in the token.
TOKEN=$(curl -s -d grant_type=client_credentials -d client_id=ai-gateway \
  -d client_secret=$SECRET http://localhost:8081/realms/ai-lab/protocol/openid-connect/token | jq -r .access_token)
curl http://$GW/v1/chat/completions -H "Authorization: Bearer $TOKEN" ...
```

Replace `gateway/03-ai-routes/security-policy.yaml` (API keys) with
`gateway-jwt-policy.yaml` — **one SecurityPolicy per Gateway**.
Alternatives: Dex, Authentik, Zitadel.
