#!/usr/bin/env bash
# Tests for bin/distill-said-at.sh against fixture transcripts in the real Claude Code and Codex
# line formats. Every fixture lives in a mktemp dir; nothing touches ~/.claude or ~/.codex.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/bin/distill-said-at.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
expect() { local name="$1" want="$2"; shift 2; local got; got=$("$@"); if [ "$got" = "$want" ]; then echo "PASS  $name"; else echo "FAIL  $name: want '$want', got '$got'"; fail=1; fi; }

# Claude Code: a user message, the agent's own grep for it (tool_use), the grep's output
# (tool_result), a meta line quoting it, and a phrase the user said twice.
cat > "$T/claude.jsonl" <<'J'
{"type":"summary","summary":"a first line with no timestamp, as Claude Code writes"}
{"type":"user","message":{"role":"user","content":"hello"},"timestamp":"2026-10-04T08:00:00.000Z"}
{"type":"user","message":{"role":"user","content":"use spaces not tabs, four of them"},"timestamp":"2026-10-12T16:40:00.000Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"distill-said-at.sh t.jsonl 'use spaces not tabs'"}}]},"timestamp":"2026-10-13T09:00:00.000Z"}
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"x","type":"tool_result","content":"use spaces not tabs, four of them"}]},"timestamp":"2026-10-13T09:00:01.000Z"}
{"type":"user","isMeta":true,"message":{"role":"user","content":"reminder: use spaces not tabs"},"timestamp":"2026-10-13T09:00:02.000Z"}
{"type":"user","message":{"role":"user","content":"name branches with initials"},"timestamp":"2026-10-05T09:12:00.000Z"}
{"type":"user","message":{"role":"user","content":"again: name branches with initials"},"timestamp":"2026-10-11T10:00:00.000Z"}
{"isSidechain":false,"attachment":{"type":"queued_command","prompt":"stop, use the staging bucket","origin":{"kind":"human"},"timestamp":"2026-10-11T12:00:00.000Z","humanTurn":true},"type":"attachment","timestamp":"2026-10-11T12:00:00.000Z"}
{"isSidechain":false,"attachment":{"type":"queued_command","prompt":"automated: use the prod bucket","origin":{"kind":"agent"},"timestamp":"2026-10-11T12:05:00.000Z"},"type":"attachment","timestamp":"2026-10-11T12:05:00.000Z"}
J
expect "claude: unique user message" "2026-10-12T16:40:00.000Z" "$SCRIPT" "$T/claude.jsonl" "use spaces not tabs"
expect "claude: phrase said twice is unknown" "unknown" "$SCRIPT" "$T/claude.jsonl" "name branches with initials"
expect "claude: longer phrase resolves it" "2026-10-11T10:00:00.000Z" "$SCRIPT" "$T/claude.jsonl" "again: name branches with initials"
expect "claude: agent-only text is unknown" "unknown" "$SCRIPT" "$T/claude.jsonl" "distill-said-at.sh"
expect "claude: message typed mid-turn counts" "2026-10-11T12:00:00.000Z" "$SCRIPT" "$T/claude.jsonl" "use the staging bucket"
expect "claude: queued command not from a human does not" "unknown" "$SCRIPT" "$T/claude.jsonl" "use the prod bucket"
expect "claude: session start" "2026-10-04T08:00:00.000Z" "$SCRIPT" "$T/claude.jsonl" --session-start

# Codex rollout, current format: user turns are response_item messages with role user.
cat > "$T/codex.jsonl" <<'J'
{"timestamp":"2026-10-04T08:00:00.000Z","type":"session_meta","payload":{"id":"s"}}
{"timestamp":"2026-10-05T09:12:00.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"name branches with initials"}]}}
{"timestamp":"2026-10-05T09:13:00.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"ok, name branches with initials"}]}}
{"timestamp":"2026-10-05T09:14:00.000Z","type":"response_item","payload":{"type":"function_call","arguments":"{\"cmd\":\"grep name branches with initials\"}"}}
J
expect "codex: user turn only" "2026-10-05T09:12:00.000Z" "$SCRIPT" "$T/codex.jsonl" "name branches with initials"
expect "codex: session start" "2026-10-04T08:00:00.000Z" "$SCRIPT" "$T/codex.jsonl" --session-start

# Codex rollout, older format: each user turn appears as a response_item AND a user_message
# event; only the event counts, so the duplicate does not make it ambiguous.
cat > "$T/codex-old.jsonl" <<'J'
{"timestamp":"2026-10-04T08:00:00.000Z","type":"session_meta","payload":{"id":"s"}}
{"timestamp":"2026-10-05T09:12:00.100Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"name branches with initials"}]}}
{"timestamp":"2026-10-05T09:12:00.200Z","type":"event_msg","payload":{"type":"user_message","message":"name branches with initials"}}
J
expect "codex old: event, not the duplicate item" "2026-10-05T09:12:00.200Z" "$SCRIPT" "$T/codex-old.jsonl" "name branches with initials"

# Two messages with the same timestamp, and a matching message with no timestamp: both ambiguous.
cat > "$T/edge.jsonl" <<'J'
{"type":"user","message":{"role":"user","content":"pin the version"},"timestamp":"2026-10-06T10:00:00.000Z"}
{"type":"user","message":{"role":"user","content":"pin the version, really"},"timestamp":"2026-10-06T10:00:00.000Z"}
{"type":"user","message":{"role":"user","content":"drop the cache"}}
{"type":"user","message":{"role":"user","content":"flush the logs"}}
{"type":"user","message":{"role":"user","content":"drop the cache now"},"timestamp":"2026-10-07T10:00:00.000Z"}
J
expect "two messages, same timestamp, is unknown" "unknown" "$SCRIPT" "$T/edge.jsonl" "pin the version"
expect "a match without a timestamp counts" "unknown" "$SCRIPT" "$T/edge.jsonl" "drop the cache"
expect "one match with no timestamp is unknown" "unknown" "$SCRIPT" "$T/edge.jsonl" "flush the logs"

# Lines that quote the user but are not the user speaking: a compaction summary (written at
# compaction time), command output, and Codex's injected instructions.
cat > "$T/quoted.jsonl" <<'J'
{"type":"user","message":{"role":"user","content":"keep the retry budget at three"},"timestamp":"2026-10-05T09:00:00.000Z"}
{"type":"user","isCompactSummary":true,"isVisibleInTranscriptOnly":true,"message":{"role":"user","content":"Summary: the user said keep the retry budget at three"},"timestamp":"2026-10-12T10:00:01.000Z"}
{"type":"user","message":{"role":"user","content":"<bash-stdout>ship it on friday</bash-stdout>"},"timestamp":"2026-10-12T11:00:00.000Z"}
{"type":"user","isSidechain":true,"message":{"role":"user","content":"subagent: deploy on tuesday"},"timestamp":"2026-10-12T09:00:00.000Z"}
{"type":"user","message":{"role":"user","content":"<task-notification>agent says merge on monday</task-notification>"},"timestamp":"2026-10-12T09:30:00.000Z"}
J
expect "claude: sidechain prompt does not count" "unknown" "$SCRIPT" "$T/quoted.jsonl" "deploy on tuesday"
expect "claude: task notification does not count" "unknown" "$SCRIPT" "$T/quoted.jsonl" "merge on monday"
expect "claude: compaction summary does not count" "2026-10-05T09:00:00.000Z" "$SCRIPT" "$T/quoted.jsonl" "keep the retry budget at three"
grep -v '"timestamp":"2026-10-05T09:00:00' "$T/quoted.jsonl" > "$T/summary-only.jsonl"
expect "claude: summary alone is unknown, never the compaction time" "unknown" "$SCRIPT" "$T/summary-only.jsonl" "keep the retry budget at three"
expect "claude: command output does not count" "unknown" "$SCRIPT" "$T/quoted.jsonl" "ship it on friday"
cat > "$T/codex-inject.jsonl" <<'J'
{"timestamp":"2026-10-04T08:00:00.000Z","type":"session_meta","payload":{"id":"s"}}
{"timestamp":"2026-10-04T08:00:00.500Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions\n<user_instructions>never force push</user_instructions>"}]}}
{"timestamp":"2026-10-04T08:00:00.600Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>cwd</environment_context>"}]}}
J
expect "codex: injected instructions do not count" "unknown" "$SCRIPT" "$T/codex-inject.jsonl" "never force push"

expect "missing transcript is unknown" "unknown" "$SCRIPT" "$T/nope.jsonl" "x"
expect "phrase with a quote is unknown" "unknown" "$SCRIPT" "$T/claude.jsonl" 'say "hi"'
expect "empty phrase is unknown" "unknown" "$SCRIPT" "$T/claude.jsonl" ""

exit $fail
