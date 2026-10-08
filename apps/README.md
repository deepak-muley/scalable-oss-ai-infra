# Apps — learn the platform by *using* it

Infrastructure only makes sense once something real runs on it. These apps
put the platform under realistic, mixed load. Chat traffic, embeddings,
reranking, tool-calling agents and offline batch jobs all go through the
same gateway, quotas and observability.

```mermaid
flowchart LR
  subgraph apps["ns: apps / evaluation"]
    UI[Open WebUI<br/>chat UI for lab users]
    RAG[RAG service<br/>FastAPI]
    AG[Agent loop<br/>tool calling]
    MCP[MCP server<br/>k8s / prometheus / docs tools]
    BATCH[vllm run-batch Job<br/>Kueue queue: batch]
    Q[(Qdrant<br/>vector DB)]
  end
  GW[Envoy AI Gateway<br/>auth, routing, token budgets]
  subgraph models["ns: llm-serving"]
    CHAT[chat models<br/>lab-chat, Llama-3.1-8B]
    EMB[BAAI/bge-m3<br/>embeddings]
    RR[bge-reranker<br/>/v1/score]
  end
  UI --> GW
  RAG -->|/v1/embeddings| GW --> EMB
  RAG -->|/v1/chat/completions| GW --> CHAT
  RAG -->|rerank, in-cluster| RR
  RAG <--> Q
  AG -->|tools=[...]| GW
  AG <-->|MCP| MCP
  MCP -->|search_docs| RAG
  BATCH -->|s3 in/out| S3[(MinIO)]
```

| Folder | What you learn |
|---|---|
| `01-open-webui` | serving humans: streaming, auth mismatch (Bearer vs `x-api-key`), multi-model UX |
| `02-vector-db` | stateful app dependencies, persistence, RWO storage |
| `03-rag-app` | the embed → retrieve → rerank → generate pipeline, using three model types at once ("chat with the lab docs") |
| `04-agent-mcp` | tool calling in vLLM, Model Context Protocol, least-privilege RBAC for AI tools |
| `05-batch-api` | throughput-oriented offline inference under Kueue, the OpenAI batch format |

Narrative and exercises: [docs/20-apps-and-workbench.md](../docs/20-apps-and-workbench.md).
