#!/usr/bin/env bash
# Turn the kill switch on or off by writing OPA data.
# The agent has no route that does this. Port-forward OPA first:
#   kubectl -n agents port-forward svc/opa 8181:8181
#   ./kill.sh on
set -euo pipefail
MODE="${1:-on}"
case "$MODE" in
  on) VALUE=true ;;
  off) VALUE=false ;;
  *) echo "usage: $0 on|off" >&2; exit 2 ;;
esac
OPA_URL="${OPA_URL:-http://127.0.0.1:8181}"
curl -sf -X PUT "${OPA_URL}/v1/data/agents/control" \
  -H "content-type: application/json" \
  -d "{\"kill_switch\": ${VALUE}}"
echo
echo "kill_switch=${VALUE}"
