# Eval closed loop — trajectories, then a skill version

[`evaluation/02-lm-eval`](../../evaluation/02-lm-eval/README.md) scores a
checkpoint. This folder scores a **trajectory**: the tools an agent
called, in order. The same Argo shape as
[`pipelines/02-model-release-pipeline`](../../pipelines/02-model-release-pipeline/README.md)
promotes or rejects. The thing being promoted is a label on the skill
ConfigMap from folder 06, not a model alias.

A row fails when a forbidden tool appears, an expected tool is missing,
or one tool is called three or more times. `trajectories.jsonl` is a
clean suite. `trajectories-bad.jsonl` is a loop. The workflow parameter
`suite` selects which file the gate reads.

## Install

```bash
./install.sh
python3 eval_trajectories.py
SUITE=bad python3 eval_trajectories.py ; echo "exit $?"
```

The WorkflowTemplate is applied only when Argo's CRD is present. Argo
must list `agents` in `workflowNamespaces`. That entry is in
[`pipelines/01-argo-workflows/values.yaml`](../../pipelines/01-argo-workflows/values.yaml).
Re-run that folder's `install.sh` if the controller was installed before
this change.

## Submit

```bash
argo submit -n agents --from workflowtemplate/skill-release --watch
kubectl -n agents get configmap agent-skills -o yaml | grep promoted

argo submit -n agents --from workflowtemplate/skill-release -p suite=bad --watch
```

The passing run sets `agents.lab/promoted-skill` and
`agents.lab/promoted-version`. The failing run prints a rejection and
leaves the annotation where the last passing run put it. A controller
would then roll the worker's skill mount to that version. This lab
stops at the annotation, which is the gate you can see.
