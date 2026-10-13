---
name: cost-watch
description: Watch agent token spend and tool-call loops.
---

# Cost watch

Look for an agent that is looping or spending tokens faster than its budget.
Report the agent, the tool, and the reason. Do not restart anything.

## Tools

- query_prometheus
- search_docs

## Instructions

1. Call query_prometheus for agent_tool_calls_total and agent_tokens_total.
2. If one tool accounts for most of the calls, say so and stop.
3. search_docs only to cite the alert rule in agents/08-decision-traces.
