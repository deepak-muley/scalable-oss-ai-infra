#!/usr/bin/env bash
# Eval-gated promotion of the candidate behind the "lab-chat" alias.
#   promote.sh                    move 100% of lab-chat to the candidate if the gate passes
#   promote.sh --canary 10        send 10% (weighted backendRefs), keep 90% on current
#   promote.sh --tolerance 0.02   allow candidate to be up to 0.02 below baseline
#   promote.sh --force            skip the gate (you own the consequences)
#   promote.sh --rollback         restore the backendRefs saved before the last promotion
#
# How: read AIGatewayRoute ai-gateway/lab-models, find the rule matching
# x-ai-eg-model=lab-chat, save its backendRefs in an annotation, rewrite them,
# and `kubectl replace`. Done in python3 for readable JSON surgery (no jq/yq needed).
source "$(dirname "$0")/../../scripts/lib.sh"
CANARY=""; TOL="0.01"; FORCE=false; ROLLBACK=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --canary) CANARY="$2"; shift 2 ;;
    --tolerance) TOL="$2"; shift 2 ;;
    --force) FORCE=true; shift ;;
    --rollback) ROLLBACK=true; shift ;;
    *) echo "unknown arg $1"; exit 1 ;;
  esac
done
ROUTE_NS=ai-gateway; ROUTE=lab-models; ALIAS=lab-chat

if [[ "$ROLLBACK" == false && "$FORCE" == false ]]; then
  RESULT=$(kubectl -n evaluation logs job/eval-gate 2>/dev/null | grep '^GATE_RESULT' | tail -1 | sed 's/^GATE_RESULT //')
  [[ -n "$RESULT" ]] || { echo "no GATE_RESULT found — run ./run.sh first"; exit 1; }
  if ! python3 -c "import json,sys; r=json.loads(sys.argv[1]); t=float(sys.argv[2]); \
print(f\"{r['metric']}: candidate={r['candidate']:.4f} baseline={r['baseline']:.4f} tolerance={t}\"); \
sys.exit(0 if r['candidate'] >= r['baseline'] - t else 1)" "$RESULT" "$TOL"; then
    echo "GATE FAILED: not promoting. (Use --force to override.)"; exit 2
  fi
  echo "GATE PASSED"
fi

kubectl -n "$ROUTE_NS" get aigatewayroute "$ROUTE" -o json | \
python3 -c '
import json, sys
mode, canary, alias = sys.argv[1], sys.argv[2], sys.argv[3]
route = json.load(sys.stdin)
ann = route["metadata"].setdefault("annotations", {})
for k in ("kubectl.kubernetes.io/last-applied-configuration",):
    ann.pop(k, None)
for f in ("resourceVersion", "uid", "creationTimestamp", "generation", "managedFields"):
    route["metadata"].pop(f, None)
route.pop("status", None)
rule = next(r for r in route["spec"]["rules"]
            if any(h.get("value") == alias for m in r.get("matches", []) for h in m.get("headers", [])))
save_key = "ai.lab/previous-" + alias + "-backends"
if mode == "rollback":
    if save_key not in ann:
        sys.exit("nothing to roll back")
    rule["backendRefs"] = json.loads(ann.pop(save_key))
else:
    ann[save_key] = json.dumps(rule["backendRefs"])
    cand = {"name": "vllm-candidate", "modelNameOverride": "candidate"}
    if canary:
        pct = int(canary)
        current = [dict(b, weight=100 - pct) for b in json.loads(ann[save_key])[:1]]
        rule["backendRefs"] = current + [dict(cand, weight=pct)]
    else:
        rule["backendRefs"] = [cand]
print(json.dumps(route))
' "$([[ $ROLLBACK == true ]] && echo rollback || echo promote)" "$CANARY" "$ALIAS" | kubectl replace -f -

kubectl -n "$ROUTE_NS" get aigatewayroute "$ROUTE" -o json | python3 -c '
import json,sys; r=json.load(sys.stdin)
for rule in r["spec"]["rules"]:
    if any(h.get("value")=="lab-chat" for m in rule.get("matches",[]) for h in m.get("headers",[])):
        print("lab-chat ->", json.dumps(rule["backendRefs"]))'
