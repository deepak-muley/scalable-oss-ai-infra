# cert-manager — TLS certificates and webhook certs

**Why:** Several operators (Kueue, KubeRay webhooks, Kubeflow Trainer,
optionally Envoy Gateway listeners) want certificates. cert-manager is the
standard way to issue them. `selfsigned-issuer.yaml` gives you a lab CA so
you can terminate TLS on the AI gateway with `*.ai.lab` certs.
