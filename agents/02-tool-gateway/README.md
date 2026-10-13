# Tool gateway — OPA on every action

[Open Policy Agent](https://www.openpolicyagent.org) decides. This process
enforces. Llama Guard classifies text. Kyverno admits pods. The check here
is whether this tool call may run.

The allow-list is in `policy.rego` (`allow_tools`). A blueprint controller
would render that set from `AgentBlueprint.spec.policy.allowTools`. The
gateway adds `tool_calls` and `repeated_tool` from Valkey (folder 05) or
from memory if Valkey is down. `MAX_STEPS` and `MAX_REPEATS` are env vars.
Fields of the same name in the JSON body are ignored.

The kill switch is OPA data, `data.agents.control.kill_switch`. `kill.sh`
writes it. The gateway has no admin route.

## Install

```bash
./install.sh
kubectl -n agents rollout status deploy/opa
kubectl -n agents rollout status deploy/tool-gateway
```

## Examples

```bash
kubectl -n agents port-forward svc/tool-gateway 8090:8090 &
kubectl -n agents port-forward svc/opa 8181:8181 &

# allow: read tool on the skill list
curl -s localhost:8090/v1/tools/call -H 'content-type: application/json' \
  -d '{"agent":"sre-agent","skill":"cluster-read","tool":"list_pods","user":"alice"}'

# deny: not on the list
curl -s -o /dev/null -w '%{http_code}\n' localhost:8090/v1/tools/call \
  -H 'content-type: application/json' \
  -d '{"agent":"sre-agent","skill":"cluster-read","tool":"delete_pod","user":"alice"}'

# deny, then deny for a different reason, then allow
curl -s localhost:8090/v1/tools/call -H 'content-type: application/json' \
  -d '{"agent":"sre-agent","tool":"exec_code","user":"alice"}'
curl -s localhost:8090/v1/tools/call -H 'content-type: application/json' \
  -d '{"agent":"sre-agent","tool":"exec_code","user":"alice","approval":"granted"}'
curl -s localhost:8090/v1/tools/call -H 'content-type: application/json' \
  -d '{"agent":"sre-agent","tool":"exec_code","user":"alice","approval":"granted","sandbox":"gvisor"}'

./kill.sh on
curl -s localhost:8090/v1/tools/call -H 'content-type: application/json' \
  -d '{"agent":"sre-agent","skill":"cluster-read","tool":"list_pods","user":"alice"}'
./kill.sh off
```

`kubectl -n agents logs deploy/tool-gateway` prints one JSON decision per
call (what ran, whether it was allowed, and why). Folder 08 turns that
line into a trace and alerts on the `/metrics` counters.

Repeat `list_pods` four times as the same agent. The fourth call returns
`same tool repeated; circuit open` (`MAX_REPEATS` is 3).
