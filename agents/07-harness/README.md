# Two harnesses, one skill

Claude, Codex, and a local loop do not share an execution model. They can
share a skill file, a policy, and a decision record. This folder is that
seam. `loop_adapter.py` is the `apps/04` shape. `graph_adapter.py` is the
same skill as a plan node plus tool nodes, which is what LangGraph would
schedule. Neither adapter calls a model. They exist so you can see the
contract without a GPU.

A second agent discovers the first through an [A2A](https://a2a-protocol.org)
agent card at `/.well-known/agent-card.json`. `handoff.py` reads the card
and prints the skill it would delegate. Identity and policy still have to
follow that hop: the caller passes the user's token through the broker in
folder 03, and the callee's tools still go through the gateway in folder 02.

## Install

```bash
./install.sh
python3 compare_harnesses.py
```

## Examples

```bash
python3 loop_adapter.py "Is anything queueing?"
python3 graph_adapter.py "Is anything queueing?"
python3 handoff.py

kubectl -n agents port-forward svc/sre-agent-card 8080:8080
AGENT_CARD_URL=http://127.0.0.1:8080/.well-known/agent-card.json python3 handoff.py
```

`compare_harnesses.py` exits non-zero if the tool sequence differs. The
harness name on each decision is allowed to differ. That is the whole test.
