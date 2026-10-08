# Onboard / offboard a tenant

| Var | Default | Meaning |
|---|---|---|
| `TENANT` | (required) | short DNS-safe name; namespace becomes `tenant-<name>` |
| `GPU_QUOTA` | 2 | nominal GPUs in the tenant's Kueue ClusterQueue and ResourceQuota cap |
| `GPU_BORROW_LIMIT` | = GPU_QUOTA | how many idle cohort GPUs the tenant may borrow |
| `CPU_QUOTA` / `MEM_QUOTA` | 32 / 256Gi | ResourceQuota caps (requests) |
| `FAIR_WEIGHT` | 1 | Kueue fair-sharing weight (needs fairSharing enabled) |
| `TOKENS_PER_HOUR` | 1000000 | gateway token budget for the whole tenant |
| `DRY_RUN` | false | `true` = print rendered YAML only |

What `onboard-tenant.sh` does:

1. Renders `templates/*.yaml` (plain `sed` substitution of `${TENANT}` etc.)
   and applies them.
2. Writes `../tenants/<name>.env` (the tenant registry, which is safe to
   commit) and regenerates the single gateway token-budget policy with
   `render-token-budgets.sh`. Envoy Gateway allows **one**
   BackendTrafficPolicy per target, so all tenants' rules must live in one
   object. It replaces `gateway/03-ai-routes/optional-token-ratelimit.yaml`
   (same name `token-budget`).
3. Creates a tenant service API key in `ai-gateway-api-keys` (client id
   `<tenant>-svc`), and prints it once.

Token budgets key on the `x-tenant-id` header. With Keycloak JWT auth
(`security/01-identity-keycloak/gateway-jwt-policy.yaml`) it comes from the
`tenant` claim, so users can't spoof it. With plain API keys, nothing sets
`x-tenant-id`, so enforce budgets per client instead or move to JWT.

The RoleBinding subject is the group `oidc:tenant-<name>`. The `oidc:`
prefix must match the API server's `--oidc-groups-prefix` (or your
`AuthenticationConfiguration`). Adjust `GROUP_PREFIX` if yours differs.
