# Agent blueprint

A team stands up an agent by filling in this object: which harness, which
model, which skills, the tool allow-list, the sandbox, where memory lives,
which ServiceAccount, and where traces go. The GPU platform underneath
stays the one this repo already installs.

There is no controller in this lab. `kubectl apply` stores `sre-agent`.
`render.sh` prints the values a controller would copy into the worker
env, the OPA allow-list, and the RuntimeClass. Folders 01–09 are those
manifests written out by hand so each one can be installed and broken
on its own.

## Install

```bash
./install.sh
kubectl -n agents get abp
./render.sh
```

`sandbox.enabled` is false on the example because gVisor is not on a kind
node. The runtime class name is still `gvisor`, matching folder 04 and
the `exec_code` branch in `policy.rego`. Turn `enabled` on only after
`runsc` is installed.

The model name is the same Qwen build `apps/04` uses for tool calling.
The blueprint does not deploy that model. Inference stays in
`inference/` and the AI gateway.
