---
name: cluster-read
description: Read cluster state. Use for pods, queues, and lab docs.
---

# Cluster read

Answer questions about this cluster by calling tools. Do not invent pod
names or metric values.

## Tools

- list_pods
- query_prometheus
- search_docs

## Instructions

1. If the question is about a queue or latency, call query_prometheus first.
2. If the question is about what is running, call list_pods.
3. Use search_docs to explain a platform concept, after you have the facts.
4. Stop when the tools have answered the question. Do not call a tool again
   with the same arguments.
