# Batch API — offline inference at maximum throughput

A large share of real LLM traffic isn't interactive: labelling, evals,
synthetic data and nightly summarisation. The OpenAI **Batch API** format
(one JSON request per line, with a `custom_id`) is the de facto interface,
and vLLM runs it directly with **`vllm run-batch`**. That path has no HTTP
server and no gateway: the engine just consumes the file at maximum batch
size.

```bash
python gen_input.py 2000 > input.jsonl
kubectl -n mlops port-forward svc/minio 9000:9000 &
export AWS_ACCESS_KEY_ID=$(kubectl -n mlops get secret minio-creds -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
export AWS_SECRET_ACCESS_KEY=$(kubectl -n mlops get secret minio-creds -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
aws --endpoint-url http://localhost:9000 s3 cp input.jsonl s3://datasets/batch/input.jsonl
kubectl apply -f batch-job.yaml
kubectl get workloads -n evaluation          # Kueue admission
kubectl -n evaluation logs -f job/batch-ticket-labels -c vllm
```

## Batch vs online vs Ray Data

| | Online (gateway) | `vllm run-batch` (this) | Ray Data + vLLM (`training/05-jobs/rayjob-batch-inference.yaml`) |
|---|---|---|---|
| Goal | latency SLO | throughput, one GPU or one TP group | throughput across **many** GPUs, plus pre/post-processing |
| Interface | HTTP / SSE | JSONL file in, JSONL out | Python dataset pipeline (parquet, S3) |
| Scheduling | always-on Deployment | Kueue Job (`batch` queue, low priority) | Kueue RayJob |
| Scale-out | replicas | run N Jobs on input shards | automatic (Ray actors) |

## Things to try

* Measure tokens/s/GPU here against the same prompts through the gateway at
  high concurrency. The batch path should win.
* Submit a high-priority TrainJob while the batch runs and watch Kueue
  preempt it. Then think about how you'd make batch resumable (shard the
  input, skip finished `custom_id`s).
* Note the shared system prompt: prefix caching makes classification-style
  batches extremely cheap.
