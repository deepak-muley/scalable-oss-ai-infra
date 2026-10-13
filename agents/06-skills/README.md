# Skills — versioned manifests

A skill is a manifest, not a Python function baked into one server. The
shape here follows [Agent Skills](https://agentskills.io): YAML front
matter plus instructions plus the tools the skill may use. Folder 07's
adapters load these files. Folder 09 promotes a version onto this
ConfigMap.

The MCP server in [`apps/04-agent-mcp`](../../apps/04-agent-mcp/README.md)
is one hard-coded tool list. A skill can move to another harness without
rewriting that server. The allow-list in `agents/02-tool-gateway/policy.rego`
must name the same tools. The blueprint in folder 10 is the object that
would keep those two lists in sync.

## Install

```bash
./install.sh
kubectl -n agents get configmap agent-skills --show-labels
```

`agents.lab/version=0.1.0` is the installed version. The eval workflow
sets `agents.lab/promoted-version` when a suite passes. It does not
overwrite the skill body. Promotion in this lab is a label you can see,
which is enough to show the gate.

## What to notice

* `cluster-read` may call `list_pods`. `cost-watch` may not. The gateway
  allow-list is still the union, because the lab policy is one Rego file.
  A controller would publish one policy per skill.
* The instruction "do not call a tool again with the same arguments" is
  what `MAX_REPEATS` enforces when the model ignores it.
