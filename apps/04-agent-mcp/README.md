# Agents — tool calling + Model Context Protocol (MCP)

Agents are the dominant workload shape at frontier labs today: long
multi-turn loops in which the model calls tools, reads the results and
calls more tools. They stress the platform in specific ways:

* **Growing contexts** re-sent every step → prefix caching and LMCache matter a lot.
* **Many short requests per task** → TTFT dominates the user experience.
* **Tools are an attack surface** → least privilege and human-in-the-loop for writes.

## Pieces

| Piece | What |
|---|---|
| **Tool calling** (OpenAI `tools` API) | the model emits `tool_calls` JSON. In vLLM, enable it per model: `--enable-auto-tool-choice --tool-call-parser hermes` (Qwen2.5). Other families use other parsers (`llama3_json`, `mistral`, …) |
| **MCP** | an open protocol (originated at Anthropic) for exposing tools, resources and prompts to any agent or client over stdio or streamable HTTP |
| `mcp_server.py` | FastMCP server with read-only lab tools: `list_pods`, `query_prometheus`, `search_docs` (→ RAG app) |
| `agent.py` | ~70-line loop: list MCP tools → hand them to the model through the gateway → execute calls via MCP → repeat |
| `k8s/mcp-server.yaml` | Deployment + **read-only** ServiceAccount/ClusterRole (get/list pods only) |

## Run

```bash
# 1) the agent model needs tool calling; e.g. add to inference/02-vllm-basic args:
#      - --enable-auto-tool-choice
#      - --tool-call-parser=hermes
#    (1.5B models are poor at tool use; use Qwen2.5-7B-Instruct or larger)
# 2) MCP server
docker build -t mcp-lab-tools:0.1 . && kind load docker-image mcp-lab-tools:0.1 --name ai-lab
kubectl apply -f k8s/mcp-server.yaml
# 3) agent from your laptop
kubectl -n apps port-forward svc/mcp-lab-tools 8000:8000 &
kubectl -n envoy-gateway-system port-forward svc/<envoy-ai-gateway-svc> 8080:80 &
pip install -r requirements.txt
python agent.py "Is anything queueing in llm-serving? Check Prometheus and explain using the docs."
```

## Things to notice

* Watch `vllm:prefix_cache_hits` while the agent runs: each step re-sends
  the whole conversation.
* Ask for something the tools can't do ("delete pod X"). The model can only
  call what you expose, and RBAC backs that up.
* Newer **Envoy AI Gateway** releases add MCP gateway features (routing,
  auth and tool filtering for MCP servers behind the gateway). Check the
  release notes for your version. That's where centralised tool governance
  belongs at scale.
* Code-execution tools need real sandboxes (gVisor, Kata, Firecracker), never
  a plain pod.
