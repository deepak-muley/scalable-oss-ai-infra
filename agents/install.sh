#!/usr/bin/env bash
# Install the enterprise agent labs in order. Optional: not part of
# ./scripts/install-all.sh all. See docs/26-enterprise-agent-platform.md.
source "$(dirname "$0")/../scripts/lib.sh"
ROOT="$(cd "$(dirname "$0")" && pwd)"
log "Enterprise agent platform"
for step in \
  01-durable-runtime \
  02-tool-gateway \
  03-credential-broker \
  04-sandbox \
  05-memory \
  06-skills \
  07-harness \
  08-decision-traces \
  09-eval-loop \
  10-blueprint
do
  "${ROOT}/${step}/install.sh"
done
echo "Next: docs/26-enterprise-agent-platform.md and agents/01-durable-runtime/README.md"
