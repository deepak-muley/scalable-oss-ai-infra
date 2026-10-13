# Enterprise agent platform

Long-running agents on top of the GPU lab: resume after a crash, a policy
check on every tool call, short-lived credentials, a sandbox, memory,
versioned skills, two harnesses, decision traces, and a promotion gate.

Narrative: [docs/26-enterprise-agent-platform.md](../docs/26-enterprise-agent-platform.md).
The single-process MCP loop these labs grow from is
[`apps/04-agent-mcp`](../apps/04-agent-mcp/README.md).

```bash
./install.sh
kubectl -n agents get pods
```

| Folder | Installs | Example you run |
|---|---|---|
| `01-durable-runtime` | Temporal dev server + worker Deployment | `worker.py start` via `kubectl exec` |
| `02-tool-gateway` | OPA + tool gateway | `curl` allow, deny, and `kill.sh` |
| `03-credential-broker` | ServiceAccount + OpenBao policy | `exchange.sh` against Keycloak |
| `04-sandbox` | gVisor RuntimeClass | `code-exec-pod.yaml` once `runsc` is on the node |
| `05-memory` | Valkey + Postgres | `valkey-cli` and `psql` in the READMEs |
| `06-skills` | `SKILL.md` ConfigMap | the two skill files |
| `07-harness` | A2A agent card server | `compare_harnesses.py`, `handoff.py` |
| `08-decision-traces` | PrometheusRule + ServiceMonitor | `span-example.json`, gateway `/metrics` |
| `09-eval-loop` | Argo WorkflowTemplate (if Argo is installed) | `eval_trajectories.py`, then `argo submit` |
| `10-blueprint` | `AgentBlueprint` CRD + `sre-agent` | `render.sh` |

Image tags are pinned in [`versions.env`](../versions.env) and substituted
by each `install.sh`. Applying a manifest by hand leaves the placeholder
in the image name.
