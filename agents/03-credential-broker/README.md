# Credential broker

The worker may call Prometheus on Alice's behalf. It must not hold the
OpenBao token, the Keycloak client secret, or Alice's refresh token.

Two identities, on purpose:

| Identity | What it is | Lab piece |
|---|---|---|
| Workload | the pod, `system:serviceaccount:agents:agent-worker` | this ServiceAccount. SPIRE mints a SPIFFE ID for it when you opt in |
| Person | Alice, the human the agent acts for | Keycloak token exchange (RFC 8693) |

`exchange.sh` is the broker call. Input is Alice's access token. Output is
a short-lived token whose audience is the tool (`prometheus-read`). The
script reads `KEYCLOAK_CLIENT_SECRET` from the broker's environment. A
correct agent container does not have that variable.

## Install

```bash
./install.sh
# optional, real clusters only:
# INSTALL_SPIRE=true ./install.sh
```

Keycloak is [`security/01-identity-keycloak`](../../security/01-identity-keycloak/README.md).
OpenBao is [`security/02-secrets-openbao-eso`](../../security/02-secrets-openbao-eso/README.md).
This folder does not reinstall either.

## Keycloak client

In realm `ai-lab`, create a confidential client `agent-broker` with token
exchange enabled (client scopes / fine-grained admin permissions, depending
on your Keycloak version: the client needs
`token-exchange` on the target client). The user's token is the subject
token. The audience is the tool name.

```bash
kubectl -n security port-forward svc/keycloak-keycloakx-http 8081:80
export KEYCLOAK_URL=http://127.0.0.1:8081
export KEYCLOAK_CLIENT_SECRET=...          # agent-broker secret, on the broker only
export SUBJECT_TOKEN=...                   # alice's access token
./exchange.sh prometheus-read
```

Load the OpenBao policy so that path is the only credential the broker can
read for this tool:

```bash
kubectl -n agents get configmap openbao-agent-policy -o jsonpath='{.data.prometheus-read\.hcl}'
# then, once OpenBao is unsealed, write the policy from that file
```

## SPIRE

`INSTALL_SPIRE=true` installs the upstream SPIFFE Helm charts into
`spire-system` at their default values. Defaults expect a cluster where
the SPIRE agent can talk to the kubelet. On kind, treat a failed DaemonSet
as a signal to read the chart's kind notes, not as a broken lab: the
ServiceAccount and the token-exchange script are the part to understand.
