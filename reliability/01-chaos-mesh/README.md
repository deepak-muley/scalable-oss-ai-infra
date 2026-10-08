# Chaos Mesh

[Chaos Mesh](https://chaos-mesh.org) (CNCF) injects faults via CRDs:
`PodChaos` (kill/failure), `NetworkChaos` (delay/loss/partition/bandwidth),
`StressChaos` (CPU/memory), `IOChaos`, `TimeChaos`, `KernelChaos`, plus
`Schedule` (cron) and `Workflow` (multi-step game days).

```bash
./install.sh                               # containerd runtime (kind, kubeadm)
RUNTIME_SOCKET=/run/k3s/containerd/containerd.sock ./install.sh   # k3s
kubectl -n chaos-mesh port-forward svc/chaos-dashboard 2333:2333  # UI
```

The chaos daemon needs the container runtime socket to enter pod network
namespaces (tc/iptables) and cgroups (stress). Paths:

| Distro | Socket |
|---|---|
| kubeadm / kind / most | `/run/containerd/containerd.sock` |
| k3s | `/run/k3s/containerd/containerd.sock` |
| RKE2 | `/run/k3s/containerd/containerd.sock` |
| MicroK8s | `/var/snap/microk8s/common/run/containerd.sock` |

Safety: the dashboard runs without auth here (`securityMode=false`) —
lab only. Experiments are scoped by namespace + label selectors; always
set `duration`. `kubectl delete` a chaos object to stop it immediately.
