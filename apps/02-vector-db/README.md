# Vector database — Qdrant

RAG needs a place to store embeddings and run nearest-neighbour search.
[Qdrant](https://qdrant.tech) is a Rust vector DB with a simple HTTP API,
payload filtering and HNSW indexes, and a single binary that's easy to run.

```bash
./install.sh
kubectl -n apps port-forward svc/qdrant 6333:6333   # http://localhost:6333/dashboard
# in-cluster: http://qdrant.apps.svc.cluster.local:6333
```

Alternatives:

| OSS | When |
|---|---|
| **pgvector** (Postgres extension) | you already run Postgres and want SQL plus vectors and transactions |
| **Milvus** | billions of vectors, distributed, GPU indexes (heavier: etcd, MinIO, Pulsar/Kafka) |
| **Weaviate**, **OpenSearch k-NN**, **Chroma** | hybrid search, existing OpenSearch, prototyping |

Lab notes: one replica with RWO persistence is fine. At scale, shard
collections across replicas, set the replication factor ≥ 2, and snapshot to S3.
