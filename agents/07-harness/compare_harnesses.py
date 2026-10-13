"""Fail if two harnesses disagree on the tool sequence for one skill."""
from __future__ import annotations

import sys
from pathlib import Path

from contract import load_skill
from graph_adapter import run as run_graph
from loop_adapter import run as run_loop

SKILL = Path(__file__).resolve().parents[1] / "06-skills" / "cluster-read" / "SKILL.md"


def tools(decisions) -> list[str]:
    return [d.tool for d in decisions if d.tool]


def main() -> None:
    skill = load_skill(SKILL)
    task = "Is anything queueing in llm-serving?"
    loop = run_loop(skill, task)
    graph = run_graph(skill, task)
    if tools(loop) != tools(graph):
        sys.exit(f"tool sequence differs: {tools(loop)} vs {tools(graph)}")
    if {d.harness for d in loop} != {"loop"} or {d.harness for d in graph} != {"graph"}:
        sys.exit("harness name was not stamped")
    print("ok", skill.name, tools(loop))


if __name__ == "__main__":
    main()
