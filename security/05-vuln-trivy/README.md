# Trivy Operator — continuous vulnerability, misconfig & secret scanning

Scans every running workload's images (CVE `VulnerabilityReport`s), K8s
config (`ConfigAuditReport`), exposed secrets in images, RBAC, and can emit
SBOMs. CUDA/vLLM images are 10–20 GB with hundreds of OS packages — expect
many findings; focus on **fixable CRITICAL/HIGH** in internet-facing paths
(gateway, routers).

```bash
./install.sh
kubectl get vulnerabilityreports -A -o wide
kubectl get configauditreports -A
```

Model artifacts are a supply chain too: prefer **safetensors** (no pickle
code execution), scan with **ModelScan** (protectai) in your download job,
and sign/verify models with **OpenSSF model-signing** (sigstore).
