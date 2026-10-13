#!/usr/bin/env bash
# Print the env and policy inputs a controller would render for one blueprint.
#   ./render.sh
#   ./render.sh sre-agent agents
set -euo pipefail
NAME="${1:-sre-agent}"
NS="${2:-agents}"
kubectl -n "$NS" get agentblueprint "$NAME" -o go-template='harness={{.spec.harness}}
model={{.spec.model}}
skills={{range .spec.skills}}{{.}} {{end}}
max_steps={{.spec.policy.maxSteps}}
max_repeats={{.spec.policy.maxRepeatsPerTool}}
allow_tools={{range .spec.policy.allowTools}}{{.}} {{end}}
sandbox={{.spec.sandbox.runtimeClassName}} enabled={{.spec.sandbox.enabled}}
working_memory={{.spec.memory.working}}
episodic_memory={{.spec.memory.episodic}}
semantic_memory={{.spec.memory.semantic}}
service_account={{.spec.identity.serviceAccount}}
on_behalf_of={{.spec.identity.onBehalfOf}}
token_ttl={{.spec.identity.tokenTTL}}
otel={{.spec.observability.otelEndpoint}}
'
