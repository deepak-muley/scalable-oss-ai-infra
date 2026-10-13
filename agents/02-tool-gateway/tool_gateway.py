#!/usr/bin/env python3
"""Every agent tool call is a POST. OPA allows or denies it before it runs.

The process is the policy enforcement point. OPA is the decision. Counts
live in Valkey when VALKEY_URL is set, and in this process otherwise.
max_steps and max_repeats come from the environment, never from the JSON
body, so a caller cannot raise its own budget.

  OPA_URL=http://127.0.0.1:8181 python3 tool_gateway.py
  curl -s localhost:8090/v1/tools/call -H 'content-type: application/json' \\
    -d '{"agent":"sre-agent","skill":"cluster-read","tool":"list_pods","user":"alice"}'
"""
from __future__ import annotations

import json
import os
import socket
import sys
import threading
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OPA_URL = os.environ.get("OPA_URL", "http://127.0.0.1:8181").rstrip("/")
VALKEY_URL = os.environ.get("VALKEY_URL", "")
MAX_STEPS = int(os.environ.get("MAX_STEPS", "8"))
MAX_REPEATS = int(os.environ.get("MAX_REPEATS", "3"))
LISTEN = os.environ.get("LISTEN", "0.0.0.0:8090")

_lock = threading.Lock()
_steps: dict[str, int] = {}
_repeats: dict[tuple[str, str], int] = {}
_metrics: dict[tuple[str, str, str], int] = {}
_tokens: dict[str, int] = {}


def _incr_local(agent: str, tool: str) -> tuple[int, int]:
    with _lock:
        _steps[agent] = _steps.get(agent, 0) + 1
        key = (agent, tool)
        _repeats[key] = _repeats.get(key, 0) + 1
        return _steps[agent], _repeats[key]


def _valkey(cmd: list[str]) -> str | None:
    if not VALKEY_URL:
        return None
    host, _, port = VALKEY_URL.partition(":")
    payload = f"*{len(cmd)}\r\n" + "".join(
        f"${len(arg.encode())}\r\n{arg}\r\n" for arg in cmd
    )
    try:
        with socket.create_connection((host, int(port or "6379")), timeout=0.5) as sock:
            sock.sendall(payload.encode())
            data = sock.recv(128).decode()
    except OSError as exc:
        print(f"valkey unavailable ({exc}); using in-process counters", flush=True)
        return None
    if data.startswith(":"):
        return data[1:].split("\r\n", 1)[0]
    return None


def counters(agent: str, tool: str) -> tuple[int, int]:
    steps = _valkey(["INCR", f"agent:{agent}:steps"])
    repeats = _valkey(["INCR", f"agent:{agent}:tool:{tool}"])
    if steps is None or repeats is None:
        return _incr_local(agent, tool)
    return int(steps), int(repeats)


def decide(payload: dict) -> dict:
    body = json.dumps({"input": payload}).encode()
    req = urllib.request.Request(
        f"{OPA_URL}/v1/data/agents/authz/decision",
        data=body,
        headers={"content-type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        doc = json.loads(resp.read().decode())
    return doc.get("result") or {"allow": False, "reason": "opa returned no decision"}


def record(agent: str, tool: str, decision: str, tokens: int) -> None:
    with _lock:
        key = (agent, tool, decision)
        _metrics[key] = _metrics.get(key, 0) + 1
        _tokens[agent] = _tokens.get(agent, 0) + tokens


def metrics_text() -> str:
    lines = [
        "# HELP agent_tool_calls_total Tool calls the gateway decided",
        "# TYPE agent_tool_calls_total counter",
    ]
    with _lock:
        items = list(_metrics.items())
        tokens = dict(_tokens)
    for (agent, tool, decision), count in items:
        lines.append(
            f'agent_tool_calls_total{{agent="{agent}",tool="{tool}",decision="{decision}"}} {count}'
        )
    lines.append("# HELP agent_tokens_total Tokens reported on allowed calls")
    lines.append("# TYPE agent_tokens_total counter")
    for agent, count in tokens.items():
        lines.append(f'agent_tokens_total{{agent="{agent}"}} {count}')
    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        return

    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("content-type", content_type)
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path != "/metrics":
            self._send(404, b"not found\n", "text/plain")
            return
        self._send(200, metrics_text().encode(), "text/plain; version=0.0.4")

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/v1/tools/call":
            self._send(404, b'{"reason":"not found"}\n', "application/json")
            return
        length = int(self.headers.get("content-length", "0"))
        try:
            incoming = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self._send(400, b'{"reason":"invalid json"}\n', "application/json")
            return
        agent = str(incoming.get("agent") or "unknown")
        tool = str(incoming.get("tool") or "")
        steps, repeats = counters(agent, tool)
        payload = {
            "agent": agent,
            "skill": incoming.get("skill") or "",
            "tool": tool,
            "user": incoming.get("user") or "",
            "approval": incoming.get("approval") or "",
            "sandbox": incoming.get("sandbox") or "",
            "tool_calls": steps,
            "repeated_tool": repeats,
            "max_steps": MAX_STEPS,
            "max_repeats": MAX_REPEATS,
        }
        try:
            decision = decide(payload)
        except Exception as exc:  # OPA down is a closed gate, not an allow
            body = json.dumps({"allow": False, "reason": f"opa unreachable: {exc}"}).encode()
            self._send(503, body, "application/json")
            return
        allow = bool(decision.get("allow"))
        tokens = int(incoming.get("tokens") or 0) if allow else 0
        record(agent, tool, "allow" if allow else "deny", tokens)
        span = {
            "trace_id": self.headers.get("x-request-id") or uuid.uuid4().hex,
            "gen_ai.operation.name": "execute_tool",
            "gen_ai.tool.name": tool,
            "gen_ai.agent.name": agent,
            "agent.skill": payload["skill"],
            "agent.user": payload["user"],
            "agent.decision.reason": decision.get("reason"),
            "agent.decision.allow": allow,
        }
        print(json.dumps(span), flush=True)
        code = 200 if allow else 403
        self._send(code, json.dumps(decision).encode(), "application/json")


def main() -> None:
    host, _, port = LISTEN.partition(":")
    server = ThreadingHTTPServer((host, int(port or "8090")), Handler)
    print(f"tool gateway on {host}:{port or '8090'} opa={OPA_URL}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
