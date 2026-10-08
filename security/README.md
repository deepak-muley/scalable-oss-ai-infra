# Security layer — all OSS

Defence in depth for a shared GPU platform. Order of value for a lab:
**identity at the gateway → secrets → network policy → admission policy →
runtime detection → vuln scanning → AI guardrails**. Details & threat model:
[docs/12-security.md](../docs/12-security.md).

| Folder | OSS | Protects against |
|---|---|---|
| `01-identity-keycloak` | **Keycloak** (OIDC) + Envoy Gateway JWT `SecurityPolicy` | anonymous use; gives every request a user/tenant id for quotas & audit |
| `02-secrets-openbao-eso` | **OpenBao** (MPL Vault fork) + **External Secrets Operator** | HF tokens / provider keys in git or plain manifests; rotation |
| `03-policy-kyverno` | **Kyverno** | unqueued GPU jobs, `--trust-remote-code`, untrusted registries, unsigned images |
| `04-runtime-falco` | **Falco** (+ Falcosidekick UI) | shells in model pods, crypto-miners on GPU nodes, credential/weight exfiltration |
| `05-vuln-trivy` | **Trivy Operator** | known CVEs in 10–20 GB CUDA/vLLM images, misconfigs, exposed secrets; SBOMs |
| `06-ai-guardrails` | **Llama Guard** on vLLM (+ NeMo Guardrails pattern) | harmful prompts/outputs, prompt-injection classification |
| *(already in platform)* | Cilium NetworkPolicy, WireGuard encryption, Hubble; Pod Security Admission; cert-manager | lateral movement, sniffing, privileged pods, plaintext TLS gaps |

Everything installs in **audit / non-blocking** mode first. Flip to
enforce once `kubectl get policyreport -A` and Falco are quiet.
