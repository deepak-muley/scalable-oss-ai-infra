"""Loop harness: one step after another, the shape of apps/04-agent-mcp."""
from __future__ import annotations

import sys
from pathlib import Path

from contract import Decision, Skill, load_skill

NAME = "loop"


def run(skill: Skill, task: str) -> list[Decision]:
    steps: list[Decision] = []
    for tool in skill.tools:
        steps.append(Decision(
            harness=NAME,
            skill=skill.name,
            observation=task,
            tool=tool,
            reason="skill lists this tool, in order",
            node="step",
        ))
    return steps


if __name__ == "__main__":
    skill = load_skill(Path(__file__).resolve().parents[1] / "06-skills" / "cluster-read" / "SKILL.md")
    task = " ".join(sys.argv[1:]) or "Is anything queueing in llm-serving?"
    for decision in run(skill, task):
        print(decision.as_dict())
