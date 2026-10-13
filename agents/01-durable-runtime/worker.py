"""Temporal worker for one lab agent task.

The workflow is the durable part: Temporal records each activity result, so
a new worker pod continues from the last finished tool call.

  # in-cluster (temporalio is installed into the pod by install.sh)
  kubectl -n agents exec deploy/agent-worker -- \
    python /app/worker.py start "Which pods are running in llm-serving?"

  # laptop, after: pip install -r requirements.txt
  # and port-forward svc/temporal 7233 and svc/tool-gateway 8090
  TEMPORAL_ADDRESS=localhost:7233 TOOL_GATEWAY_URL=http://127.0.0.1:8090 \
    python worker.py start "Which pods are running in llm-serving?"

Replace call_tool's fixed script with the loop in apps/04-agent-mcp/agent.py
when a tool-calling model is up. Keep the activity boundary on every tool
return: that boundary is the checkpoint.
"""
from __future__ import annotations

import asyncio
import json
import os
import sys
import urllib.error
import urllib.request
import uuid
from datetime import timedelta

from temporalio import activity, workflow
from temporalio.client import Client
from temporalio.common import RetryPolicy
from temporalio.exceptions import ApplicationError
from temporalio.worker import Worker

TASK_QUEUE = os.environ.get("TASK_QUEUE", "agent-tasks")
# Fixed script so the lab run is reproducible without a GPU. Each name is
# one activity, and therefore one checkpoint.
TOOLS = ["list_pods", "query_prometheus"]


@activity.defn
def call_tool(payload: dict) -> dict:
    url = os.environ.get("TOOL_GATEWAY_URL", "").rstrip("/")
    body = json.dumps(payload).encode()
    if not url:
        return {"tool": payload["tool"], "allow": True, "reason": "no gateway configured"}
    req = urllib.request.Request(
        f"{url}/v1/tools/call",
        data=body,
        headers={"content-type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode()
        # A policy deny is not a blip. Retrying it would hammer the gateway.
        raise ApplicationError(f"tool denied: {detail}", non_retryable=True) from exc


@workflow.defn
class AgentTask:
    def __init__(self) -> None:
        self.steps: list[dict] = []

    @workflow.run
    async def run(self, task: str) -> str:
        for tool in TOOLS:
            result = await workflow.execute_activity(
                call_tool,
                {
                    "task": task,
                    "tool": tool,
                    "skill": "cluster-read",
                    "agent": "sre-agent",
                    "user": "alice",
                },
                start_to_close_timeout=timedelta(seconds=20),
                retry_policy=RetryPolicy(maximum_attempts=5),
            )
            self.steps.append(result)
        return f"did {len(self.steps)} tools for: {task}"

    @workflow.query
    def history(self) -> list[dict]:
        return list(self.steps)


async def serve() -> None:
    client = await Client.connect(os.environ.get("TEMPORAL_ADDRESS", "localhost:7233"))
    worker = Worker(
        client,
        task_queue=TASK_QUEUE,
        workflows=[AgentTask],
        activities=[call_tool],
    )
    await worker.run()


async def start(task: str) -> None:
    client = await Client.connect(os.environ.get("TEMPORAL_ADDRESS", "localhost:7233"))
    handle = await client.start_workflow(
        AgentTask.run,
        task,
        id=f"agent-task-{uuid.uuid4()}",
        task_queue=TASK_QUEUE,
    )
    print("started", handle.id)
    print(await handle.result())


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "worker"
    if cmd == "worker":
        asyncio.run(serve())
    elif cmd == "start":
        text = " ".join(sys.argv[2:]) or "Which pods are running in llm-serving?"
        asyncio.run(start(text))
    else:
        sys.exit(f"usage: {sys.argv[0]} worker|start [task]")
