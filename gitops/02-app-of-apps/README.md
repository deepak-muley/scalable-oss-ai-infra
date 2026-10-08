# App of apps — the whole platform as Argo CD Applications

```
root-app.yaml                 (apply by hand, once)
└── apps/                     (Argo CD syncs this folder)
    ├── 00-project.yaml       AppProject ai-lab                         wave -20
    ├── 10-cilium.yaml        chart + $values + lb-ipam.yaml             wave -10
    ├── 11..19                namespaces, cert-manager, NFS, GPU Operator,
    │                         monitoring, KEDA, LWS, Kueue, queues       waves -9..-4
    ├── 20..25                OpenBao, ESO, Kyverno(+policies), Falco,
    │                         Trivy, Keycloak                            wave -4
    ├── 30..33                Envoy Gateway, AI Gateway CRDs/controller,
    │                         Gateway + auth                             waves -3..-1
    ├── 40..42                model cache, vLLM production-stack, AI routes  waves 0..1
    ├── 50..54                MinIO, MLflow, KubeRay, Kubeflow Trainer(+runtimes) waves 0..1
    └── 60..61                Argo Workflows, model-release pipeline     waves 0..1
applicationset-gpu-clusters.yaml  multi-cluster example (not auto-applied)
```

## Patterns used (read the files, they are commented)

| Pattern | Example | Why |
|---|---|---|
| **Multi-source Application**: upstream chart + values from this repo (`ref: values`, `$values/...`) | `15-monitoring.yaml` | the chart stays upstream, *your* config stays in your git; the same values files the `install.sh` scripts use |
| Extra **directory source** with `include` | `15-monitoring.yaml` (podmonitors), `12-cert-manager.yaml` (issuer) | ship the chart and the CRs that configure it as one unit |
| **OCI Helm charts** | `17-lws.yaml`, `18-kueue.yaml`, `30-32` | repo registered with `enableOCI` in `01-argocd/values.yaml` |
| **Kustomize from upstream git tag** | `53-kubeflow-trainer.yaml` | the project ships kustomize, not Helm |
| **Remote values URL** | `30-envoy-gateway.yaml` | reuse upstream's extension-manager values pinned to a tag |
| `ServerSideApply=true` | monitoring, Cilium, KEDA, Kueue | huge CRDs exceed client-side-apply annotation limits |
| `SkipDryRunOnMissingResource=true` | queues, issuers, routes | CRs whose CRDs are created by an earlier wave/source |
| `ignoreDifferences` + `RespectIgnoreDifferences` | `41-vllm-stack.yaml` (`/spec/replicas`), Cilium certs | runtime owners (KEDA, Helm cert gen) vs. selfHeal |
| `prune: false` on children | all | a mistaken delete in git should not delete PVCs with 500 GB of weights |

## Things that are environment-specific (EDIT in git before syncing)

* `10-cilium.yaml` → `k8sServiceHost`; `platform/00-cilium/lb-ipam.yaml` IP range
* `13-nfs-provisioner.yaml` → `nfs.server`, `nfs.path`
* `14-gpu-operator.yaml` → `driver.enabled`
* `platform/09-kueue/queues.yaml` → GPU quotas
* Fork the repo first if you're not the owner. `repoURL` points at
  `deepak-muley/scalable-oss-ai-infra`. Find and replace it in `apps/`,
  `root-app.yaml` and `applicationset-gpu-clusters.yaml`.

## Secrets are NOT in git

`hf-token`, `minio-root` / `minio-creds`, `openbao-token`, provider keys:
create them out of band or through OpenBao + External Secrets. A GitOps repo
must be safe to make public.

## Versions: keep in sync with versions.env

Chart versions are **hardcoded** in `apps/*.yaml` and must match
`/versions.env` (used by the `install.sh` scripts). `"*"` means "latest"
wherever versions.env is empty. Pin it after your first successful sync.
At scale nobody does this by hand. **Renovate** (OSS) scans
`targetRevision`/`chart` fields in Argo CD manifests, opens PRs for new
releases, and CI + a canary cluster validate them before merge.

## Bootstrap order

```bash
platform/00-cilium/install.sh          # CNI first (pods need it)
gitops/01-argocd/install.sh
kubectl apply -f gitops/02-app-of-apps/root-app.yaml
kubectl -n argocd get applications -w  # watch waves go Synced/Healthy
```
