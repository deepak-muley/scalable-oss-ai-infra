# Image pre-pulling — kill the biggest cold-start cost

Cold start of a vLLM replica on a fresh node:

| Step | Typical time |
|---|---|
| pull `vllm/vllm-openai` (~10 GB compressed) over 1 GbE | **~90 s**; 10 GbE ~10 s; from Docker Hub with rate limits: minutes |
| load 16 GB of weights from NFS at 1 GB/s | ~16 s (seconds from local NVMe page cache) |
| CUDA graph capture + warmup | 10–60 s |

Autoscaling and failover can't be faster than this. The DaemonSet here
pulls the heavy images onto every GPU node ahead of time: each image runs
as an **initContainer that exits immediately**, which forces the kubelet to
pull it. A tiny `pause` container then keeps the pod alive, so the images
stay referenced and aren't garbage-collected.

```bash
kubectl apply -f prepull-daemonset.yaml
kubectl -n kube-system get pods -l app=gpu-image-prepull -o wide
```

Keep the image list in sync with the tags you actually deploy. A
pre-pulled `latest` doesn't help a pod that asks for `v0.10.2`.

## Beyond a lab: P2P image distribution

With 100s of nodes, everyone pulling 10 GB from one registry at once is
its own outage. Peer-to-peer distribution lets nodes fetch layers from each
other:

* **Spegel**: stateless, uses containerd's local content store; no extra storage.
  ```bash
  helm upgrade --install spegel oci://ghcr.io/spegel-org/helm-charts/spegel \
    --namespace spegel --create-namespace
  ```
  (Spegel needs containerd registry mirror config; see its docs for your distro.)
* **Dragonfly** (CNCF): P2P with a scheduler and seed peers, and can also
  distribute model files.
* Also: an in-lab pull-through registry cache (Harbor or `registry:2` proxy)
  to dodge Docker Hub rate limits.
