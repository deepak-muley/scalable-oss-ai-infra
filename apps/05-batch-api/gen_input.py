"""Generate an OpenAI-batch-format JSONL file for `vllm run-batch`.

  python gen_input.py 1000 > input.jsonl
  aws --endpoint-url $AWS_ENDPOINT_URL s3 cp input.jsonl s3://datasets/batch/input.jsonl
"""
import json
import sys

MODEL = "Qwen/Qwen2.5-1.5B-Instruct"
SYSTEM = "You label customer support tickets. Reply with exactly one word: billing, bug, feature, or other."
TICKETS = [
    "I was charged twice this month",
    "The export button crashes the app",
    "Please add dark mode",
    "How do I change my username?",
]

n = int(sys.argv[1]) if len(sys.argv) > 1 else 100
for i in range(n):
    print(json.dumps({
        "custom_id": f"ticket-{i}",
        "method": "POST",
        "url": "/v1/chat/completions",
        "body": {
            "model": MODEL,
            "messages": [
                {"role": "system", "content": SYSTEM},   # identical prefix => prefix-cache hits
                {"role": "user", "content": f"Ticket #{i}: {TICKETS[i % len(TICKETS)]}"},
            ],
            "max_tokens": 4,
            "temperature": 0,
        },
    }))
