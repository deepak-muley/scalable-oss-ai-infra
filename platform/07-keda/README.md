# KEDA — event-driven autoscaling

The HPA scales on CPU/memory, which is meaningless for GPU inference.
KEDA lets us scale vLLM replicas on **queue depth / KV-cache pressure**
straight from Prometheus queries (see `inference/06-autoscaling`).
It can also scale to zero (useful for rarely-used models in a lab).
