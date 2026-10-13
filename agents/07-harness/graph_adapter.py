"""Graph harness: a plan node, then one tool node per tool.

This is the same control flow LangGraph would express as two nodes. The
dependency stays out of the lab so the contract is visible in one file.
"""
from __future__ import annotations

import sys
from pathlib import Path

from contract import Decision, Skill, load_skill

NAME = "graph"


def run(skill: Skill, task: str) -> list[Decision]:
    steps = [Decision(
        harness=NAME,
        skill=skill.name,
        observation=task,
        tool=None,
        reason="plan from the skill instructions before any tool",
        node="plan",
    )]
    for tool in skill.tools:
        steps.append(Decision(
            harness=NAME,
            skill=skill.name,
            observation=task,
            tool=tool,
            reason="skill lists this tool, in order",
            node="tool",
        ))
    return steps


if __name__ == "__main__":
    skill = load_skill(Path(__file__).resolve().parents[1] / "06-skills" / "cluster-read" / "SKILL.md")
    task = " ".join(sys.argv[1:]) or "Is anything queueing in llm-serving?"
    for decision in run(skill, task):
        print(decision.as_dict())
