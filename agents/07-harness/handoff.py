#!/usr/bin/env python3
"""Read an A2A agent card and print the skill a second agent would delegate to.

  python3 handoff.py
  AGENT_CARD_URL=http://127.0.0.1:8080/.well-known/agent-card.json python3 handoff.py
"""
import json
import os
import sys
import urllib.request
from pathlib import Path

LOCAL = Path(__file__).with_name("agent-card.json")


def load() -> dict:
    url = os.environ.get("AGENT_CARD_URL", "")
    if url:
        with urllib.request.urlopen(url, timeout=5) as resp:
            return json.loads(resp.read().decode())
    return json.loads(LOCAL.read_text())


def main() -> None:
    card = load()
    skills = card.get("skills") or []
    if not skills:
        sys.exit(f"agent card {card.get('name')} publishes no skills")
    skill = skills[0]
    print(f"delegate to {card['name']} at {card['url']}")
    print(f"skill {skill['id']}: {skill['description']}")


if __name__ == "__main__":
    main()
