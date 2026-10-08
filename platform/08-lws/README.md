# LeaderWorkerSet (LWS)

A Kubernetes SIG API for **multi-node, multi-pod replicas**: one "replica" =
1 leader pod + N worker pods that are created, scheduled, restarted and
scaled *as a unit*. This is how you serve a model that does not fit on one
node (e.g. DeepSeek-V3/R1, Llama-405B) with vLLM tensor-parallel within a
node and pipeline-parallel across nodes.

Used by: `inference/05-model-catalog/llm-multinode-lws.yaml`, llm-d, KServe,
NVIDIA Dynamo, SGLang deployments.
