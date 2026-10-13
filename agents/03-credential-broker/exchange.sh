#!/usr/bin/env bash
# Exchange a user's access token for a short-lived token scoped to one tool.
# The agent never sees KEYCLOAK_CLIENT_SECRET. Run this on the broker, or
# as a platform admin demonstrating the call the broker makes.
#
# Keycloak must allow token exchange (RFC 8693) for client "agent-broker"
# in realm "ai-lab". See the README. This script does not change Keycloak.
set -euo pipefail
: "${KEYCLOAK_URL:?set KEYCLOAK_URL, e.g. http://127.0.0.1:8081}"
: "${KEYCLOAK_CLIENT_SECRET:?set the agent-broker client secret}"
: "${SUBJECT_TOKEN:?set the user access token to exchange}"
TOOL="${1:-prometheus-read}"
REALM="${KEYCLOAK_REALM:-ai-lab}"
CLIENT="${KEYCLOAK_CLIENT_ID:-agent-broker}"
curl -sS -X POST \
  "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
  -d grant_type=urn:ietf:params:oauth:grant-type:token-exchange \
  -d "client_id=${CLIENT}" \
  -d "client_secret=${KEYCLOAK_CLIENT_SECRET}" \
  -d "subject_token=${SUBJECT_TOKEN}" \
  -d "audience=${TOOL}" \
  -d requested_token_type=urn:ietf:params:oauth:token-type:access_token
echo
