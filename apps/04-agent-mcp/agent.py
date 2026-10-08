"""Tiny agent loop: OpenAI tool calling through the AI gateway, tools served over MCP.

  GATEWAY_URL=http://localhost:8080 MCP_URL=http://localhost:8000/mcp \
    python agent.py "Are any vLLM pods queueing requests right now? Explain why with the docs."

Requires the chat model to be served with tool calling enabled in vLLM:
  --enable-auto-tool-choice --tool-call-parser hermes        (Qwen2.5 family)
SDK APIs (openai, mcp) drift; this targets openai>=1.40, mcp>=1.9.
"""
import asyncio
import json
import os
import sys

from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client
from openai import AsyncOpenAI

GATEWAY_URL = os.environ.get("GATEWAY_URL", "http://localhost:8080").rstrip("/")
MCP_URL = os.environ.get("MCP_URL", "http://localhost:8000/mcp")
MODEL = os.environ.get("AGENT_MODEL", "Qwen/Qwen2.5-7B-Instruct")
MAX_STEPS = int(os.environ.get("MAX_STEPS", "8"))

llm = AsyncOpenAI(base_url=f"{GATEWAY_URL}/v1", api_key="unused",
                  default_headers={"x-api-key": os.environ.get("GATEWAY_API_KEY", "sk-lab-alice-change-me")})


async def main(task: str) -> None:
    async with streamablehttp_client(MCP_URL) as (read, write, _):
        async with ClientSession(read, write) as mcp:
            await mcp.initialize()
            # MCP tool schemas are JSON Schema -> map 1:1 onto OpenAI function tools
            tools = [{"type": "function",
                      "function": {"name": t.name, "description": t.description or "",
                                   "parameters": t.inputSchema}}
                     for t in (await mcp.list_tools()).tools]
            print("tools:", [t["function"]["name"] for t in tools])

            messages = [
                {"role": "system", "content": "You are an SRE assistant for an AI lab cluster. "
                                              "Use tools to gather facts before answering. Be concise."},
                {"role": "user", "content": task},
            ]
            for step in range(MAX_STEPS):
                resp = await llm.chat.completions.create(model=MODEL, messages=messages, tools=tools)
                msg = resp.choices[0].message
                messages.append(msg.model_dump(exclude_none=True))
                if not msg.tool_calls:
                    print("\n=== answer ===\n" + (msg.content or ""))
                    return
                for call in msg.tool_calls:
                    args = json.loads(call.function.arguments or "{}")
                    print(f"[step {step}] {call.function.name}({args})")
                    result = await mcp.call_tool(call.function.name, args)
                    text = "\n".join(getattr(c, "text", "") for c in result.content)
                    messages.append({"role": "tool", "tool_call_id": call.id, "content": text[:8000]})
            print("stopped: max steps reached")


if __name__ == "__main__":
    asyncio.run(main(" ".join(sys.argv[1:]) or "Which pods are running in llm-serving?"))
