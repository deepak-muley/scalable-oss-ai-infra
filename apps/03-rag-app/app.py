"""Minimal-but-real RAG service: embed -> retrieve (Qdrant) -> rerank (vLLM) -> generate (gateway).

Every model call goes through the lab's platform:
  * embeddings + chat   -> Envoy AI Gateway (auth, routing, token metering)
  * reranking           -> vllm-reranker in-cluster (/rerank, Cohere/Jina-compatible)
"""
import os
import re
import uuid

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, PointStruct, VectorParams

GATEWAY_URL = os.environ["GATEWAY_URL"].rstrip("/")          # http://<envoy-svc>.envoy-gateway-system.svc.cluster.local
API_KEY = os.environ.get("GATEWAY_API_KEY", "")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://qdrant.apps.svc.cluster.local:6333")
COLLECTION = os.environ.get("COLLECTION", "lab-docs")
EMBED_MODEL = os.environ.get("EMBED_MODEL", "BAAI/bge-m3")
CHAT_MODEL = os.environ.get("CHAT_MODEL", "lab-chat")
RERANK_URL = os.environ.get("RERANK_URL", "")               # e.g. http://vllm-reranker.llm-serving.svc.cluster.local:8000
RERANK_MODEL = os.environ.get("RERANK_MODEL", "BAAI/bge-reranker-v2-m3")
CHUNK_CHARS = int(os.environ.get("CHUNK_CHARS", "1200"))
CHUNK_OVERLAP = int(os.environ.get("CHUNK_OVERLAP", "200"))

app = FastAPI(title="lab-rag")
http = httpx.Client(timeout=120, headers={"x-api-key": API_KEY} if API_KEY else {})
qdrant = QdrantClient(url=QDRANT_URL)


class Document(BaseModel):
    source: str
    text: str


class IngestRequest(BaseModel):
    documents: list[Document]


class AskRequest(BaseModel):
    question: str
    top_k: int = 20          # candidates from vector search
    top_n: int = 5           # kept after reranking


def chunk(text: str) -> list[str]:
    """Split markdown on headings, then window long sections with overlap."""
    sections = re.split(r"\n(?=#{1,4} )", text)
    chunks = []
    for sec in sections:
        sec = sec.strip()
        start = 0
        while start < len(sec):
            chunks.append(sec[start:start + CHUNK_CHARS])
            start += CHUNK_CHARS - CHUNK_OVERLAP
    return [c for c in chunks if len(c) > 50]


def embed(texts: list[str]) -> list[list[float]]:
    r = http.post(f"{GATEWAY_URL}/v1/embeddings", json={"model": EMBED_MODEL, "input": texts})
    r.raise_for_status()
    return [d["embedding"] for d in sorted(r.json()["data"], key=lambda d: d["index"])]


def ensure_collection(dim: int) -> None:
    if not qdrant.collection_exists(COLLECTION):
        qdrant.create_collection(COLLECTION, vectors_config=VectorParams(size=dim, distance=Distance.COSINE))


def rerank(query: str, docs: list[str]) -> list[int]:
    """Return doc indices ordered by cross-encoder relevance (falls back to vector order)."""
    if not RERANK_URL or not docs:
        return list(range(len(docs)))
    r = http.post(f"{RERANK_URL}/rerank", json={"model": RERANK_MODEL, "query": query, "documents": docs})
    r.raise_for_status()
    results = sorted(r.json()["results"], key=lambda x: x["relevance_score"], reverse=True)
    return [x["index"] for x in results]


@app.get("/healthz")
def healthz():
    return {"ok": True}


@app.post("/ingest")
def ingest(req: IngestRequest):
    total = 0
    for doc in req.documents:
        pieces = chunk(doc.text)
        if not pieces:
            continue
        for i in range(0, len(pieces), 32):                 # batch embedding calls
            batch = pieces[i:i + 32]
            vectors = embed(batch)
            ensure_collection(len(vectors[0]))
            points = [
                PointStruct(
                    # deterministic id => re-ingesting the same doc overwrites instead of duplicating
                    id=str(uuid.uuid5(uuid.NAMESPACE_URL, f"{doc.source}#{i + j}")),
                    vector=vec,
                    payload={"source": doc.source, "chunk": i + j, "text": text},
                )
                for j, (text, vec) in enumerate(zip(batch, vectors))
            ]
            qdrant.upsert(COLLECTION, points=points)
            total += len(points)
    return {"chunks": total, "collection": COLLECTION}


@app.post("/search")
def search(req: AskRequest):
    if not qdrant.collection_exists(COLLECTION):
        raise HTTPException(404, "nothing ingested yet")
    qvec = embed([req.question])[0]
    hits = qdrant.query_points(COLLECTION, query=qvec, limit=req.top_k, with_payload=True).points
    docs = [h.payload["text"] for h in hits]
    order = rerank(req.question, docs)[: req.top_n]
    return [{"source": hits[i].payload["source"], "score": hits[i].score, "text": docs[i]} for i in order]


@app.post("/ask")
def ask(req: AskRequest):
    passages = search(req)
    context = "\n\n".join(f"[{n + 1}] ({p['source']})\n{p['text']}" for n, p in enumerate(passages))
    messages = [
        {"role": "system", "content": (
            "Answer using ONLY the numbered context passages. Cite them like [1], [2]. "
            "If the context does not contain the answer, say you don't know.")},
        {"role": "user", "content": f"Context:\n{context}\n\nQuestion: {req.question}"},
    ]
    r = http.post(f"{GATEWAY_URL}/v1/chat/completions",
                  json={"model": CHAT_MODEL, "messages": messages, "temperature": 0.2, "max_tokens": 512})
    r.raise_for_status()
    body = r.json()
    return {
        "answer": body["choices"][0]["message"]["content"],
        "sources": [{"n": n + 1, "source": p["source"]} for n, p in enumerate(passages)],
        "usage": body.get("usage"),
    }
