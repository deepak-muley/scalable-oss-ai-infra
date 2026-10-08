# Kyverno — admission policies as Kubernetes YAML

Policies here (all start in **Audit**; results in `PolicyReport`s):

| Policy | Why |
|---|---|
| `require-kueue-queue` | GPU batch jobs in `training`/`evaluation` must go through Kueue — no quota bypass |
| `disallow-trust-remote-code` | `--trust-remote-code` executes arbitrary Python from a model repo inside your GPU pod |
| `restrict-image-registries` | model-serving pods only from vetted registries |
| `require-gpu-limits-and-requests` | every container asking for GPUs also sets memory requests (no noisy neighbours / OOM storms) |
| `verify-image-signatures` | cosign/sigstore verification for *your* images (example) |

```bash
./install.sh
kubectl get clusterpolicy
kubectl get policyreport -A        # what would have been blocked
# enforce one: kubectl patch clusterpolicy disallow-trust-remote-code --type merge \
#   -p '{"spec":{"validationFailureAction":"Enforce"}}'
```
Alternative: OPA Gatekeeper (Rego), or built-in ValidatingAdmissionPolicy (CEL).
