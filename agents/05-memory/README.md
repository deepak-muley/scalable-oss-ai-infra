# Agent memory — working, episodic, semantic

The RAG index in [`apps/02-vector-db`](../../apps/02-vector-db/README.md)
stores lab documents. Agent memory is a different store: what this run
was doing, what it already did, and what it should recall next week.
Mixing them means a document ingest can overwrite an agent's own notes.

| Tier | Keeps | Lab |
|---|---|---|
| Working | the current thread, expiring | Valkey key `agent:{name}:working:{thread}`, TTL one hour |
| Episodic | the decision log, durable | Postgres table `episodes` |
| Semantic | embeddings of past episodes | Qdrant collection `agent-semantic`, not the docs collection |

The tool gateway (folder 02) uses a fourth key family for budgets:
`agent:{name}:steps` and `agent:{name}:tool:{tool}`. Those are counters,
not memories. They live in the same Valkey so a replica of the gateway
sees one count.

## Install

```bash
./install.sh
kubectl -n agents rollout status deploy/valkey
kubectl -n agents rollout status deploy/postgres
```

Both use emptyDir. A deleted pod forgets. For a lab that is the right
default; put a PVC on `/data` and `/var/lib/postgresql/data` when the
episodes matter. The password `lab-only-change-me` is a lab default, in
the same spirit as the Keycloak admin password.

## Examples

```bash
kubectl -n agents exec deploy/valkey -- \
  valkey-cli SET agent:sre-agent:working:thread-1 "which pods are queueing" EX 3600
kubectl -n agents exec deploy/valkey -- \
  valkey-cli GET agent:sre-agent:working:thread-1

kubectl -n agents exec deploy/postgres -- \
  psql -U agent -d agent_memory -c \
  "INSERT INTO episodes (agent, user_id, skill, observation, action, reason)
   VALUES ('sre-agent', 'alice', 'cluster-read',
           'queue depth is 3', 'query_prometheus', 'skill says to check the queue');"
kubectl -n agents exec deploy/postgres -- \
  psql -U agent -d agent_memory -c "SELECT agent, action, reason FROM episodes;"
```

Semantic recall reuses Qdrant (`http://qdrant.apps.svc.cluster.local:6333`)
with a collection named `agent-semantic`. Create that collection the same
way [`apps/03-rag-app`](../../apps/03-rag-app/README.md) creates the docs
collection, and keep the names distinct. Embed the `observation` and
`reason` columns, not the raw prompt log.
