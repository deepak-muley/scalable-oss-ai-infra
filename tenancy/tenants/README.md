# Tenant registry

One `<tenant>.env` per onboarded tenant, written by
`01-onboard-tenant/onboard-tenant.sh`. It's the source for the generated
gateway token-budget policy. Keep it in git: it records who has which quota.
No secrets go here.
