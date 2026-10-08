"""MCP server exposing read-only lab tools to agents.

Uses the official `mcp` Python SDK (FastMCP). Transport: streamable HTTP at /mcp.
SDK APIs evolve; this targets mcp>=1.9.
"""
import os

import httpx
from kubernetes import client, config
from mcp.server.fastmcp import FastMCP

PROM_URL = os.environ.get("PROM_URL", "http://kps-prometheus.monitoring.svc:9090")
RAG_URL = os.environ.get("RAG_URL", "http://rag-app.apps.svc.cluster.local")
# Defence in depth: RBAC is read-only, and we further limit which namespaces are visible.
ALLOWED_NAMESPACES = set(os.environ.get(
    "ALLOWED_NAMESPACES", "llm-serving,training,evaluation,ai-gateway,apps").split(","))

mcp = FastMCP("lab-tools", host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))

try:
    config.load_incluster_config()
except config.ConfigException:
    config.load_kube_config()          # local dev
core = client.CoreV1Api()


@mcp.tool()
def list_pods(namespace: str) -> str:
    """List pods in a lab namespace with phase, node, restarts and GPU requests."""
    if namespace not in ALLOWED_NAMESPACES:
        return f"namespace not allowed; choose one of {sorted(ALLOWED_NAMESPACES)}"
    rows = []
    for p in core.list_namespaced_pod(namespace).items:
        gpus = sum(int((c.resources.limits or {}).get("nvidia.com/gpu", 0)) for c in p.spec.containers)
        restarts = sum(cs.restart_count for cs in (p.status.container_statuses or []))
        rows.append(f"{p.metadata.name}\t{p.status.phase}\tnode={p.spec.node_name}\trestarts={restarts}\tgpus={gpus}")
    return "\n".join(rows) or "no pods"


@mcp.tool()
def query_prometheus(promql: str) -> str:
    """Run an instant PromQL query, e.g. sum by (model_name)(vllm:num_requests_waiting)."""
    r = httpx.get(f"{PROM_URL}/api/v1/query", params={"query": promql}, timeout=30)
    r.raise_for_status()
    result = r.json()["data"]["result"][:50]
    return "\n".join(f"{s['metric']} = {s['value'][1]}" for s in result) or "empty result"


@mcp.tool()
def search_docs(question: str) -> str:
    """Search the lab documentation (RAG app retrieval + rerank) and return top passages."""
    r = httpx.post(f"{RAG_URL}/search", json={"question": question, "top_n": 3}, timeout=60)
    r.raise_for_status()
    return "\n\n".join(f"({p['source']})\n{p['text']}" for p in r.json())


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
