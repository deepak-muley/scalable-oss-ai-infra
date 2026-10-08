# RAG app — "chat with the lab docs"

A ~170-line FastAPI service that exercises **three model types** through the
platform:

```
/ingest : markdown ─► chunk (by heading, 1200 chars, 200 overlap)
                   ─► /v1/embeddings (BAAI/bge-m3 via AI gateway) ─► Qdrant upsert
/ask    : question ─► embed ─► Qdrant top-20 ─► /rerank (bge-reranker, in-cluster) top-5
                   ─► /v1/chat/completions (lab-chat via gateway) with [n] citations
/search : same as /ask without generation (debug retrieval quality)
```

Prereqs: `apps/02-vector-db`, the embedding and reranker models
(`inference/05-model-catalog/embedding-and-reranker.yaml`), gateway routes
for `BAAI/bge-m3` and `lab-chat`.

```bash
docker build -t rag-app:0.1 .
kind load docker-image rag-app:0.1 --name ai-lab        # kind; or push to your registry
vi k8s/rag-app.yaml                                     # set GATEWAY_URL (Envoy svc name)
kubectl apply -f k8s/rag-app.yaml
kubectl apply -f k8s/ingest-docs-job.yaml && kubectl -n apps logs -f job/ingest-lab-docs

kubectl -n apps port-forward svc/rag-app 8090:80
curl -s localhost:8090/ask -H 'content-type: application/json' \
  -d '{"question":"How does Kueue decide when a TrainJob may start?"}' | jq
```

`ingest_docs.py` is the same script the Job uses, so you can run it locally
against a port-forward (`DOCS_DIR=../.. RAG_URL=http://localhost:8090 python ingest_docs.py`).

## Things to try

* Switch reranking off (`RERANK_URL=""`) and compare answers and `/search` results.
* Change chunk size and overlap, re-ingest, and compare.
* Watch the gateway token metrics while asking questions. Embeddings are
  cheap; long-context chat is not.
* Put the system prompt first and keep it stable, so that prefix caching
  and LMCache hit on every request (see the vLLM prefix-cache metrics).
