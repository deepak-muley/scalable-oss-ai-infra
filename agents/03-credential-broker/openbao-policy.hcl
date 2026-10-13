# Lab policy for OpenBao (Vault API). Load it after security/02 is up:
#   kubectl -n security exec statefulset/openbao -- \
#     bao policy write agent-tool-prometheus /policies/prometheus-read.hcl
#
# The broker's workload identity may read this one path. The agent process
# does not get a token that can read anything else.
path "agents/creds/prometheus-read" {
  capabilities = ["read"]
}
