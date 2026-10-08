# Distributed tracing — OpenTelemetry Collector + Tempo

Metrics tell you *that* p95 TTFT is bad; a trace tells you *why* for one
request: time in the gateway, in the router, **queued inside vLLM**,
**prefill**, **decode**.

```
client ─► Envoy (span: route, upstream, x-ai-eg-model tag)
             └─► vLLM (span "llm_request": gen_ai.* attributes,
                       queue time, time-to-first-token, e2e, token counts)
   all spans ─OTLP─► otel-collector.observability:4317 ─► Tempo ─► Grafana
```

## Install

```bash
./install.sh                     # namespace observability: Tempo + Collector + Grafana datasource
```

## 1. Turn on vLLM tracing

vLLM emits OpenTelemetry spans when started with `--otlp-traces-endpoint`,
**but the OpenTelemetry Python packages are not in the default image**.
Build a thin image (`Dockerfile.vllm-otel`) and push it to your registry:

```bash
docker build -f Dockerfile.vllm-otel -t <registry>/vllm-openai-otel:v0.10.2 .
```

Then patch a deployment (example: `inference/02-vllm-basic`):

```bash
kubectl -n llm-serving patch deploy vllm-qwen-7b --type json --patch-file vllm-tracing-patch.json
kubectl -n llm-serving set image deploy/vllm-qwen-7b vllm=<registry>/vllm-openai-otel:v0.10.2
```

`--collect-detailed-traces` (`model`, `worker`, `all`) adds per-step timing
but costs throughput — enable only while investigating.

## 2. Turn on Envoy Gateway tracing

`envoyproxy-tracing.yaml` creates an `EnvoyProxy` with an OpenTelemetry
tracing provider pointed at the collector and tags spans with the model
name. Attach it to the Gateway (**version-dependent**: Gateway-level
`infrastructure.parametersRef` needs Gateway API ≥ v1.1 and Envoy Gateway ≥
v1.2; alternatively set it on the GatewayClass `spec.parametersRef`):

```bash
kubectl apply -f envoyproxy-tracing.yaml
kubectl -n ai-gateway patch gateway ai-gateway --type merge -p \
 '{"spec":{"infrastructure":{"parametersRef":{"group":"gateway.envoyproxy.io","kind":"EnvoyProxy","name":"ai-gateway-telemetry"}}}}'
```

This re-renders the Envoy Deployment (brief restart of the proxy pods).
Envoy propagates W3C `traceparent` to vLLM, so both spans join one trace.

The Envoy **AI Gateway** ext_proc can also emit OpenInference/gen_ai
spans (prompt/response metadata) — controlled by `OTEL_*` env on the
AI Gateway helm values in recent releases. Keep prompt *content* capture
off unless you have consent (see docs/12-security.md).

## 3. Exemplars: dashboard → trace in one click

Two settings in `platform/06-monitoring/values.yaml` (not changed
automatically — add them yourself):

```yaml
prometheus:
  prometheusSpec:
    enableFeatures: [exemplar-storage]
grafana:
  sidecar:
    datasources:
      exemplarTraceIdDestinations:
        datasourceUid: tempo
        traceIdLabelName: trace_id
```

vLLM attaches exemplars to its histograms only on versions that support
it; Envoy and your own apps (OTel SDK) do.
