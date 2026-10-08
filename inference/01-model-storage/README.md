# Model storage — HF token, shared model cache, pre-download

Every vLLM pod in this lab mounts the same RWX PVC `model-cache` at
`/models` and sets `HF_HOME=/models/hf`. The first pod (or the
`download-model` Job) downloads weights once; every later replica — on any
node — starts from the shared copy. This is the single biggest win for
fast scale-up.

```bash
kubectl -n llm-serving create secret generic hf-token --from-literal=token=hf_xxx
kubectl apply -f model-cache-pvc.yaml
# pre-pull a model (edit MODEL in the Job):
kubectl apply -f download-model-job.yaml && kubectl -n llm-serving logs -f job/download-model
```

Gated models (Llama, Gemma, Mistral-large…) need you to accept the licence
on huggingface.co with the account that owns the token.

Air-gapped / no-HF labs: put weights in MinIO (training/01) and use
`vllm serve /models/<dir>` or vLLM's `--load-format runai_streamer` with an
`s3://` path.
