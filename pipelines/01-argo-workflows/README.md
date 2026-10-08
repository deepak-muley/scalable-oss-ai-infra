# Argo Workflows

A workflow engine for Kubernetes: each step is a container **or a Kubernetes
resource** (create a RayJob and wait for `status.jobStatus == SUCCEEDED`).
That second ability is why it fits an AI platform: the pipeline *drives the
platform's own operators* instead of re-implementing them.

| File | |
|---|---|
| `values.yaml` | lab settings: server auth mode, which namespaces run workflows, MinIO artifact/log archive, TTL & pod GC |
| `rbac.yaml` | `model-release` ServiceAccount (ns `training`) + least-privilege Roles in `training`, `llm-serving`, `ai-gateway`, `evaluation` |

```bash
./install.sh                     # requires training/01-object-storage (minio-creds) for log archiving
kubectl -n argo port-forward svc/argo-workflows-server 2746:2746
# UI: http://localhost:2746   (auth-mode=server: NO login — lab only!)
# CLI: brew install argo
```

Production: `authModes: [sso]` with Keycloak OIDC, workflow archive in
Postgres, per-team namespaces with their own ServiceAccounts, Argo Events
for triggers (new data in S3 → pipeline).

What the RBAC shows: a pipeline is a *privileged actor* — it can deploy
models and flip production traffic. Scope it to exactly the verbs it needs
(see `rbac.yaml`), and gate promotion on evals or human approval.
