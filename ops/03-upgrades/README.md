# Upgrades runbook

The AI-infra stack ships monthly, and several APIs are alpha. Upgrades are
where labs lose days. Treat every bump as a small, reversible change.

## Principles

1. **One layer at a time, one component at a time.** Never bump
   `versions.env` wholesale.
2. **Canary on kind first.** Run `kind/up.sh` with the new pins, then
   `kind/test.sh`. Most breakages (CRD field renames, chart value changes,
   webhook issues) show up here in 15 minutes.
3. **Read the release notes for CRD changes.** `helm upgrade` does **not**
   upgrade CRDs in a chart's `crds/` directory; many projects ship separate
   CRD charts or manifests for this reason.
4. **Snapshot first:** `velero backup create pre-upgrade-<component>`.
5. **Pin images too** (vLLM, LMCache, Ray), not just charts.

## Procedure

```bash
./scripts/check-latest-versions.sh          # what moved
git switch -c bump-<component>-<version>
vi versions.env                             # ONE component
helm diff upgrade ...                       # helm plugin install https://github.com/databus23/helm-diff
cd kind && ./up.sh && ./test.sh             # canary
velero backup create pre-upgrade-<component>
./<layer>/<component>/install.sh            # real cluster
./scripts/verify.sh && cd kind && ./test.sh # (adapt) + watch dashboards 24h
git commit -am "bump <component> to <version>"
```

## Order (dependencies first)

```
cert-manager → Cilium → GPU Operator → Prometheus stack → KEDA / LWS / Kueue
→ Envoy Gateway → Envoy AI Gateway (compatible pair!) → Inference Extension
→ KubeRay / Trainer → vLLM / LMCache images → apps
```

## Component caveats

| Component | Watch out for |
|---|---|
| **Cilium** | upgrade one minor at a time (1.17 → 1.18, never skip). Run `cilium upgrade` pre-flight checks. The datapath restarts per node, so roll nodes gradually. Check that `kubeProxyReplacement` and LB-IPAM CRD versions (`v2alpha1` → `v2`) still match your manifests |
| **GPU Operator** | driver container upgrades **evict GPU pods on that node** (drain). Use the operator's driver-upgrade controller (`driver.upgradePolicy`, maxUnavailable). Check driver ↔ CUDA ↔ vLLM image compatibility |
| **Kueue** | API moving `v1beta1` → `v1beta2`. Read the conversion notes. Admitted workloads survive the restart, but test preemption after an upgrade |
| **Envoy Gateway + AI Gateway** | must be a **compatible pair** (AI GW release notes). Upgrade the AI GW CRD chart first, then EG with the new AI GW values file, then the AI GW controller. `AIGatewayRoute` fields have changed between minors (`targetRefs` → `parentRefs`, `schema` removal) |
| **Inference Extension** | v1 `InferencePool` is stable, but `InferenceObjective` and EPP config are alpha |
| **KubeRay** | CRD upgrade is manual (`kubectl apply --server-side -f ray-operator/config/crd`). Ray image versions inside RayClusters are independent: bump them separately |
| **Kubeflow Trainer** | runtimes (`ClusterTrainingRuntime`) are versioned with the controller, so re-apply the runtimes overlay |
| **vLLM** | CLI flags and metric names get renamed (`gpu_cache_usage_perc` → `kv_cache_usage_perc`, `--task` → `--runner`). Update KEDA queries and dashboards in the same change |

## Kubernetes minor upgrades with GPU nodes

1. Upgrade control plane(s) first (`kubeadm upgrade plan/apply`).
2. For each GPU node:
   * **Training:** check `kubectl get workloads -A`. Either wait for jobs on
     that node to finish, or stop Kueue from admitting onto it (cordon). Kueue
     re-queues preempted jobs, so make sure they checkpoint.
   * **LWS groups:** draining one pod restarts the **whole group**
     (`RecreateGroupOnPodRestart`), so a 2-node model is down until both are
     back. Do it in a maintenance window or keep a second replica.
   * **Online vLLM:** use PodDisruptionBudgets (`minAvailable: 1`) per model
     so drains wait for a replacement to become Ready.
   * `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`, then
     upgrade kubelet, then `kubectl uncordon`.
3. Re-run `./scripts/verify.sh` and the smoke tests.

## Rollback

* Helm: `helm rollback <release> <rev> -n <ns>`. **CRDs are not rolled
  back**: if a new CRD version was stored, rolling back the controller may not
  understand it. That's why the canary stage exists.
* Config: `velero restore create --from-backup pre-upgrade-<component>`.
* Images: revert the tag in git and re-apply.
