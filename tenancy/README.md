# Multi-tenancy — sharing one GPU platform between teams

A frontier lab is multi-tenant internally (research teams, product teams,
eval, safety) and externally (API customers). This folder automates
onboarding a **tenant** (team) with isolation at every layer:

| Layer | Mechanism | File |
|---|---|---|
| Namespace + Pod Security | `Namespace` labelled `ai.lab/tenant`, PSA baseline | `templates/namespace.yaml` |
| Hard resource caps | `ResourceQuota` (GPUs, CPU, memory, PVCs) + `LimitRange` defaults | `templates/quota.yaml` |
| GPU scheduling share | Kueue `ClusterQueue` in cohort `ai-lab` (nominal quota, borrowing, fair-share weight) + `LocalQueue` | `templates/kueue.yaml` |
| Network isolation | `CiliumNetworkPolicy`: default deny, allow DNS, AI gateway, MinIO/MLflow | `templates/network.yaml` |
| Access control | `RoleBinding` of OIDC group `tenant-<name>` (Keycloak) → `edit` | `templates/rbac.yaml` |
| API access + token budget | gateway API key for the tenant service account; per-tenant token budget keyed on `x-tenant-id` | `onboard-tenant.sh`, `render-token-budgets.sh` |

```bash
cd 01-onboard-tenant
TENANT=search GPU_QUOTA=4 TOKENS_PER_HOUR=2000000 ./onboard-tenant.sh
TENANT=search ./offboard-tenant.sh
```

## Soft vs hard multi-tenancy

* **Soft** (trusted internal teams), which is this folder: shared cluster
  and nodes, isolation by namespace, quota, network policy and RBAC. The
  threats are mistakes and noisy neighbours, not attackers.
* **Hard** (untrusted tenants or external customers): add **dedicated
  nodes** per tenant (taints + Kueue flavors), sandboxed runtimes (gVisor,
  Kata) for code-executing workloads, separate model-server pools and KV
  caches, per-tenant encryption keys, or **separate clusters**
  (vCluster/Capsule/Kamaji give virtual control planes in between).

## Noisy neighbours on GPUs

GPUs isolate badly compared to CPUs:

* **Whole-GPU allocation** is the default and the safest choice.
* **Time-slicing has no memory isolation**: one tenant's OOM or a hung
  kernel affects the others. Don't share time-sliced GPUs across tenants.
* **MIG** gives hardware isolation of memory and SMs. It's the right tool
  for multi-tenant small workloads on A100/H100+.
* Shared resources remain even with whole GPUs: PCIe/NVLink bandwidth, node
  CPU and RAM (dataloaders), local NVMe, and NICs during NCCL all-reduce.
  Topology-aware placement and per-tenant node pools help.
* Shared **model servers** (one vLLM serving many tenants) need fairness at
  the gateway (token budgets, priorities). One tenant's 100k-token prompts
  raise everyone's TTFT.

## KV-cache isolation

Prefix caching, LMCache sharing and cache-aware routing reuse KV across
requests. Across tenants that creates a **timing side channel**: a fast
TTFT reveals that someone recently sent the same prefix. Options:

* separate engine pools (or separate LMCache stores) per sensitive tenant
* salt the cache per tenant (newer vLLM versions support a per-request
  `cache_salt` so identical prefixes from different tenants don't share
  blocks; check your version)
* disable cross-tenant sharing tiers and keep only per-pod caching

## Fair sharing

`templates/kueue.yaml` sets `fairSharing.weight` on each tenant's
ClusterQueue. It only takes effect when Kueue's configuration enables fair
sharing (`fairSharing: {enable: true}` in the manager config; see
`platform/09-kueue/values.yaml`). Without it, borrowing is first-come, and
preemption follows `reclaimWithinCohort`.
