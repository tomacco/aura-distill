#!/usr/bin/env bash
# distill-said-at -- when did the user say this? Reads a Claude Code or Codex transcript (JSONL).
#
#   distill-said-at.sh <transcript.jsonl> <phrase>        UTC timestamp of the one user message
#                                                         containing <phrase>, else "unknown"
#   distill-said-at.sh <transcript.jsonl> --session-start first timestamp in the transcript
#
# Only messages the user typed count: Claude Code "type":"user" lines (and queued_command attachments
# from a human, typed mid-turn) that are not tool results,
# meta lines, compaction summaries, subagent (sidechain) prompts, task notifications or command output; Codex "user_message" events, or "role":"user"
# response items (minus injected instructions and environment context) in rollouts with no such
# events. A compaction summary quotes the user but carries the compaction time, so it never counts. The agent's own tool calls and their output never match, so a search for
# the phrase does not find itself. Two or more matching messages print "unknown": the caller
# picks a longer phrase. The phrase must not contain quotes, backslashes or line breaks (JSON
# escapes them in the transcript). Prints "unknown" for any failure; never guesses. Exit 0.

transcript="${1:-}"
phrase="${2:-}"
unknown() { echo unknown; exit 0; }

[ -r "$transcript" ] && [ -n "$phrase" ] || unknown
first_ts() { grep -o '"timestamp":"[^"]*"' | head -1 | sed 's/^"timestamp":"//; s/"$//'; }

if [ "$phrase" = "--session-start" ]; then
    ts=$(first_ts < "$transcript")
    [ -n "$ts" ] && echo "$ts" || unknown
    exit 0
fi

case "$phrase" in *'"'*|*'\'*|*$'\n'*) unknown ;; esac

if grep -q '"type":"user_message"' "$transcript"; then
    user_lines() { grep '"type":"user_message"' "$transcript"; }
elif grep -q '"type":"session_meta"' "$transcript"; then
    user_lines() { grep '"type":"response_item"' "$transcript" | grep '"role":"user"' |
        grep -v -e '<user_instructions>' -e '<environment_context>' -e '# AGENTS.md instructions'; }
else
    user_lines() {
        grep '"type":"user"' "$transcript" | grep -v -e '"tool_result"' -e '"isMeta":true' \
            -e '"isCompactSummary":true' -e '"isVisibleInTranscriptOnly":true' -e '"isSidechain":true' \
            -e '<task-notification>' \
            -e '<bash-stdout>' -e '<bash-stderr>' -e '<local-command-stdout>'
        # A message typed while the agent is working is stored as a queued_command attachment.
        grep '"type":"queued_command"' "$transcript" | grep '"origin":{"kind":"human"}'
    }
fi

matches=$(user_lines | grep -F -- "$phrase")
[ -n "$matches" ] && [ "$(printf '%s\n' "$matches" | wc -l | tr -d ' ')" = 1 ] || unknown
ts=$(printf '%s\n' "$matches" | first_ts)
[ -n "$ts" ] && echo "$ts" || unknown
