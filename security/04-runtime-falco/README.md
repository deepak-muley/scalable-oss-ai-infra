# Falco — runtime threat detection (eBPF)

GPU nodes are juicy targets: crypto-miners, stolen model weights, leaked
HF/provider tokens. Falco watches syscalls on every node and alerts on
suspicious behaviour. `values.yaml` adds lab-specific rules:

* interactive shell inside a model-serving/training container
* known GPU crypto-miner binaries
* reads of service-account tokens / cloud creds by model servers
* outbound connections from `llm-serving` pods to non-cluster IPs (exfil)

Alerts → Falcosidekick → UI (and Slack/Alertmanager/Loki if configured).

```bash
./install.sh
kubectl -n security port-forward svc/falco-falcosidekick-ui 2802:2802
kubectl -n llm-serving exec -it deploy/vllm-qwen-7b -- bash   # triggers a WARNING
```
Alternative/complement: **Tetragon** (Cilium) — eBPF observability *and*
in-kernel enforcement (kill the process).
