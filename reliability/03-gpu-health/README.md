# GPU health — detect, cordon, validate (the toy version)

Hyperscalers run whole teams and systems for this: continuous health
checks, automatic cordon/drain, repair workflows, burn-in before a node
rejoins. This folder builds the **minimal version** so you understand the
moving parts:

| Piece | File | Role |
|---|---|---|
| node-problem-detector (NPD) | `install.sh`, `npd-values.yaml` | DaemonSet watching the kernel log; turns `NVRM: Xid` lines into node **events** and a `GPUHardwareProblem` **node condition** |
| DCGM metrics | (GPU Operator) | `DCGM_FI_DEV_XID_ERRORS`, ECC, NVLink counters in Prometheus |
| remediator | `gpu-health-remediator.yaml` | CronJob: queries Prometheus + node conditions, **cordons** nodes with fatal XIDs, labels them `ai.lab/gpu-health=bad` (dry-run by default) |
| pre-flight | `dcgm-diag-job.yaml` | `dcgmi diag -r 2` on a node's GPUs before it (re)joins the pool |

```bash
./install.sh                                   # NPD
kubectl apply -f gpu-health-remediator.yaml    # DRY_RUN=true: only logs what it would do
kubectl -n gpu-health logs -l job-name --tail=50
kubectl get nodes -L ai.lab/gpu-health
kubectl describe node <gpu-node> | grep -A3 GPUHardwareProblem
```

Flip `DRY_RUN` to `"false"` in the CronJob when you trust it. It
deliberately does **not** drain by default — evicting a training job loses
work since the last checkpoint; better to let the job fail/restart on its
own and keep new work off the node. Set `DRAIN=true` for serving-only nodes.

Keep bad nodes out of new scheduling everywhere: cordon handles the
default scheduler; Kueue flavors and your vLLM manifests can additionally
use `nodeAffinity` on `ai.lab/gpu-health NotIn [bad]`.

Real-world tools to read about next: NVIDIA DCGM health watches and
`dcgmi diag` levels (1 quick → 4 long burn-in), NVIDIA's
`nvidia-bug-report.sh`, nccl-tests for fabric validation, and Kubernetes
node-problem-detector + Draino/"node-healthcheck-operator" style remediation.

> Caveat: `DCGM_FI_DEV_XID_ERRORS` carries a `Hostname` label that is the
> node's hostname — usually equal to the Kubernetes node name, but not
> always. The remediator maps it as-is; adjust if your names differ.
