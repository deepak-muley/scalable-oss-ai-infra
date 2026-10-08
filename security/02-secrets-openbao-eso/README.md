# Secrets — OpenBao + External Secrets Operator

* **OpenBao** — Linux Foundation, MPL-2.0 fork of HashiCorp Vault (same API).
  The source of truth for HF tokens, external provider API keys, MinIO creds,
  gateway client keys.
* **External Secrets Operator (ESO)** syncs selected paths into Kubernetes
  Secrets (`ExternalSecret`) and refreshes them — rotate in OpenBao, pods
  pick it up on restart (or via Reloader).

Lab mode: OpenBao `dev` server (in-memory, root token `root`). Real setups:
HA Raft storage, auto-unseal, Kubernetes auth method instead of a token.

```bash
./install.sh
kubectl -n security exec -it openbao-0 -- bao kv put secret/ai-lab/huggingface token=hf_xxx
kubectl apply -f external-secrets.yaml
kubectl -n llm-serving get externalsecret,secret hf-token
```
