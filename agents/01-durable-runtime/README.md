# Durable agent runtime — Temporal

An enterprise agent runs for longer than a process. [Temporal](https://temporal.io)
records every completed activity. Delete the worker pod and the new pod
replays history and continues at the next tool call. Training checkpoints
in [`lifecycle/02-pretrain`](../../lifecycle/02-pretrain/README.md) solve
the same problem for gradient steps. This folder solves it for tool calls.

`server start-dev` is the lab server: one container, SQLite on an emptyDir,
Web UI on port 8233. It is not the production deployment. That is the
[temporalio Helm chart](https://github.com/temporalio/helm-charts) with
Postgres, a frontend service, and a matching history shard count.

## Install

```bash
./install.sh
kubectl -n agents rollout status deploy/temporal
kubectl -n agents rollout status deploy/agent-worker
```

The worker container installs `temporalio` into `/tmp/py` on every start
(the image is stock `python:3.12-slim`). The startup probe waits for that
import. The first pull plus pip takes a minute.

## Run

```bash
kubectl -n agents port-forward svc/temporal 8233:8233
# UI: http://localhost:8233  namespace default, task queue agent-tasks

kubectl -n agents exec deploy/agent-worker -- \
  python /app/worker.py start "Which pods are running in llm-serving?"
```

The workflow runs two activities, `list_pods` then `query_prometheus`.
Each one POSTs to the tool gateway from folder 02. If that Service does
not exist yet, the activity retries, then fails. Install folder 02 first,
or start the workflow after `./agents/install.sh`.

## What to notice

* Open the workflow in the UI. Two activities, two results. That history
  is the checkpoint. There is no checkpoint file in the agent container.
* Delete the pod during a run (`kubectl -n agents delete pod -l app=agent-worker`).
  The Deployment brings it back, Temporal replays the finished activity,
  and the run completes. A laptop script in `apps/04` cannot do this.
* A policy deny is `non_retryable`. A connection error retries up to 5
  times. Those are different failures and the workflow treats them differently.

Swap the fixed tool list in `worker.py` for the MCP loop in
`apps/04-agent-mcp/agent.py` when a tool-calling model is served. Keep one
activity per tool return.
