#!/usr/bin/env python3
"""Render a Claude Code JSONL transcript into a plain-text conversation.

Deterministic and model-agnostic: user text, assistant text, tool calls (name +
truncated input) and truncated tool results. This is what a background
auto-distiller would feed to a model — every candidate gets byte-identical input.
"""
import json
import sys

TOOL_INPUT_MAX = 400
TOOL_RESULT_MAX = 600


def trunc(s: str, n: int) -> str:
    s = s.strip()
    return s if len(s) <= n else s[:n] + f" …[+{len(s) - n} chars]"


def content_blocks(msg):
    c = msg.get("content")
    if isinstance(c, str):
        return [{"type": "text", "text": c}]
    return c or []


def render(path: str) -> str:
    out = []
    turn = 0
    for line in open(path, encoding="utf-8"):
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        t = d.get("type")
        if t not in ("user", "assistant"):
            continue
        msg = d.get("message", {})
        for b in content_blocks(msg):
            bt = b.get("type")
            if bt == "text":
                txt = b["text"]
                if t == "user" and txt.startswith("<"):  # system reminders, hook context
                    continue
                turn += 1
                out.append(f"[{turn}] {'USER' if t == 'user' else 'ASSISTANT'}:\n{txt.strip()}\n")
            elif bt == "tool_use":
                inp = json.dumps(b.get("input", {}), ensure_ascii=False)
                out.append(f"  >> TOOL {b.get('name')}: {trunc(inp, TOOL_INPUT_MAX)}\n")
            elif bt == "tool_result":
                rc = b.get("content")
                if isinstance(rc, list):
                    rc = "\n".join(x.get("text", "") for x in rc if isinstance(x, dict))
                out.append(f"  << RESULT: {trunc(str(rc or ''), TOOL_RESULT_MAX)}\n")
    return "\n".join(out)


if __name__ == "__main__":
    sys.stdout.write(render(sys.argv[1]))
