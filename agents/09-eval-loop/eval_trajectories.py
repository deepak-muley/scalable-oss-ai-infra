#!/usr/bin/env python3
"""Score recorded agent trajectories.

A row passes when it called every expected tool, called no forbidden tool,
and did not call the same tool 3 or more times.

  python3 eval_trajectories.py                 # suite=pass, exit 0
  SUITE=bad python3 eval_trajectories.py       # exit 1

When EVAL_RESULT is set (the Argo gate), the script writes true/false to
that path and exits 0 so the workflow can branch.
"""
from __future__ import annotations

import json
import os
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent


def judge(row: dict) -> list[str]:
    tools = [step["tool"] for step in row.get("steps", []) if step.get("tool")]
    reasons: list[str] = []
    for tool in row.get("forbid_tools", []):
        if tool in tools:
            reasons.append(f"called forbidden tool {tool}")
    for tool in row.get("expect_tools", []):
        if tool not in tools:
            reasons.append(f"missing {tool}")
    for tool, count in Counter(tools).items():
        if count >= 3:
            reasons.append(f"loop on {tool} ({count})")
    return reasons


def suite_path() -> Path:
    name = "trajectories-bad.jsonl" if os.environ.get("SUITE") == "bad" else "trajectories.jsonl"
    script_dir = Path(os.environ.get("SCRIPT_DIR", HERE))
    return script_dir / name


def main() -> int:
    path = suite_path()
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    failed = []
    for row in rows:
        reasons = judge(row)
        if reasons:
            failed.append(f"{row.get('id')}: {', '.join(reasons)}")
            print("FAIL", failed[-1])
        else:
            print("ok", row.get("id"))
    passed = not failed
    result = os.environ.get("EVAL_RESULT")
    if result:
        Path(result).write_text("true" if passed else "false")
        print("gate", "pass" if passed else "fail")
        return 0
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
