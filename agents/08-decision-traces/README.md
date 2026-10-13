# Decision traces

[`observability/03-tracing`](../../observability/03-tracing/README.md)
follows one model request through Envoy and vLLM: queue, prefill, decode.
An agent trace has to answer a different question: what it saw, which tool
it chose, and why the gateway allowed it.

The tool gateway prints that record as one JSON line per call. The field
names follow the OpenTelemetry GenAI semantic conventions where those
conventions already exist (`gen_ai.operation.name`, `gen_ai.tool.name`,
`gen_ai.agent.name`). `agent.decision.reason` and `agent.skill` are lab
attributes. `span-example.json` is the same shape, written out so you can
diff a log line against it.

## Install

```bash
./install.sh
```

The PrometheusRule and ServiceMonitor apply only when the Prometheus
Operator CRDs are already installed (`platform/06-monitoring`). The
operator in this lab selects rules and monitors from every namespace.

## What to look at

```bash
kubectl -n agents port-forward svc/tool-gateway 8090:8090
curl -s localhost:8090/v1/tools/call -H 'content-type: application/json' \
  -d '{"agent":"sre-agent","skill":"cluster-read","tool":"list_pods","user":"alice","tokens":100}'
kubectl -n agents logs deploy/tool-gateway --tail=1
curl -s localhost:8090/metrics | head
```

`tokens` on the request is how a harness reports model usage for that
step. The gateway adds it to `agent_tokens_total` only when the call is
allowed. `AgentToolLoop` fires when one agent/tool pair increases by more
than 15 calls in 5 minutes. `AgentCostAnomaly` fires above 20000 tokens
in 10 minutes. Both thresholds are lab-sized so a script can trip them.

To land the same fields in Tempo, point the gateway's stdout at the
collector you already run, or have the worker emit an OTLP span with
these attributes. The collector config in `observability/03-tracing`
does not need a new backend for that.
