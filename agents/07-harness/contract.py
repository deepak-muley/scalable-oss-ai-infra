"""Shared skill and decision shape for every harness adapter."""
from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass
class Skill:
    name: str
    description: str
    tools: list[str]
    instructions: str


@dataclass
class Decision:
    harness: str
    skill: str
    observation: str
    tool: str | None
    reason: str
    node: str

    def as_dict(self) -> dict:
        return asdict(self)


def load_skill(path: str | Path) -> Skill:
    text = Path(path).read_text()
    meta: dict[str, str] = {}
    body = text
    if text.startswith("---\n"):
        _, front, body = text.split("---\n", 2)
        for line in front.splitlines():
            if ":" in line:
                key, value = line.split(":", 1)
                meta[key.strip()] = value.strip()
    tools: list[str] = []
    in_tools = False
    for line in body.splitlines():
        if line.startswith("## Tools"):
            in_tools = True
            continue
        if line.startswith("## ") and in_tools:
            break
        if in_tools and line.startswith("- "):
            tools.append(line[2:].strip())
    if not meta.get("name"):
        raise ValueError(f"skill {path} has no name in front matter")
    return Skill(
        name=meta["name"],
        description=meta.get("description", ""),
        tools=tools,
        instructions=body.strip(),
    )
