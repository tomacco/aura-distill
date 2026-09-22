#!/usr/bin/env python3
"""Render a Claude Code JSONL transcript into a plain-text conversation.

Deterministic and model-agnostic: user text, assistant text, tool calls (name +
truncated input) and truncated tool results. This is what a background
auto-distiller would feed to a model — every candidate gets byte-identical input.
"""
import json
import re
import sys

# Only these wrappers are harness-injected. A user message that merely starts with "<"
# (pasted XML, a <path> placeholder, a diff fragment) is real content and must survive.
SYSTEM_BLOCK = re.compile(r"\s*<(system-reminder|command-name|command-message|command-args|"
                          r"local-command-stdout|user-prompt-submit-hook|task-notification)\b")

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
    turns = {"user": 0, "assistant": 0}
    dropped = 0
    for line in open(path, encoding="utf-8"):
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        t = d.get("type")
        if t not in ("user", "assistant"):
            continue
        if d.get("isSidechain"):  # sub-agent traffic is not session conversation
            continue
        msg = d.get("message", {})
        for b in content_blocks(msg):
            bt = b.get("type")
            if bt == "text":
                txt = b["text"]
                if t == "user" and SYSTEM_BLOCK.match(txt):  # system reminders, hook context
                    dropped += 1
                    continue
                # Number each role separately: "the 9th turn" must mean the same thing to a
                # reader, to the model, and to the counts reported alongside the results.
                turns[t] += 1
                role = "USER" if t == "user" else "ASSISTANT"
                out.append(f"[{role[0]}{turns[t]}] {role}:\n{txt.strip()}\n")
            elif bt == "tool_use":
                inp = json.dumps(b.get("input", {}), ensure_ascii=False)
                out.append(f"  >> TOOL {b.get('name')}: {trunc(inp, TOOL_INPUT_MAX)}\n")
            elif bt == "tool_result":
                rc = b.get("content")
                if isinstance(rc, list):
                    rc = "\n".join(x.get("text", "") for x in rc if isinstance(x, dict))
                out.append(f"  << RESULT: {trunc(str(rc or ''), TOOL_RESULT_MAX)}\n")
    if dropped:
        # A silently eaten user turn would corrupt the very signals this harness measures.
        print(f"render_transcript: skipped {dropped} system-injected user block(s)", file=sys.stderr)
    return "\n".join(out)


if __name__ == "__main__":
    sys.stdout.write(render(sys.argv[1]))
