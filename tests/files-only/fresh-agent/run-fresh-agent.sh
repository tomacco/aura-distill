#!/usr/bin/env bash
# run-fresh-agent.sh — manual, live-model validation of the files-only runtime (#78).
#
# A fresh headless Claude Code agent, with no memory, no profile instructions and no MCP
# servers, follows ONLY the shipped instructions (distill-process.md, distill-monitor.md,
# the Codex integration wording) against a synthetic store in a temp dir:
#
#   A. migrate-store --preview, then --apply (lifecycle enabled) on a copy of
#      tests/files-only/store-before; the shipped checker must then pass against both the
#      agent's own backup and the pristine fixture.
#   B. five retrieval questions, each in a new session, against the migrated store:
#      a read_with companion, a protected rule, an archived recall, a scoped miss and a
#      pinned project. Each answer is graded by required phrases; the store must be
#      byte-identical afterwards (retrieval writes nothing, archives are read-only).
#
# Not run in CI: it needs a logged-in `claude` CLI and costs model tokens. It never reads
# or writes a real knowledge store: the agent never loads user settings or the user's
# CLAUDE.md and rules (--setting-sources local or project, from a temp working directory),
# has no MCP servers and no session persistence, and on macOS runs inside sandbox-exec with
# the real stores and profile instruction files denied.
#
# Usage: tests/files-only/fresh-agent/run-fresh-agent.sh
#   MODEL=sonnet (default) | opus | haiku
#   SURFACE=claude (default): retrieval sessions load the shipped rules/distill.md and the
#           Claude managed block as the working directory's CLAUDE.md, as Claude Code does
#   SURFACE=codex: retrieval sessions get the Codex managed block as appended system prompt
#   REUSE=<work dir of an earlier run>: skip part A and ask the questions against a copy of
#           that run's migrated store
#   KEEP=1 (default) keeps the temp dir, which is always printed; STEP_TIMEOUT=1500 seconds per session
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
MODEL=${MODEL:-sonnet}
SURFACE=${SURFACE:-claude}
case "$SURFACE" in claude|codex) ;; *) echo "SURFACE must be claude or codex" >&2; exit 2 ;; esac
STEP_TIMEOUT=${STEP_TIMEOUT:-1500}
command -v claude >/dev/null 2>&1 || { echo "claude CLI not found" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found (used to read the transcripts)" >&2; exit 2; }

T=$(mktemp -d "${TMPDIR:-/tmp}/aura-fresh-agent.XXXXXX")
T=$(cd "$T" && pwd -P)
STORE="$T/store"; WORK="$T/work"; LOGS="$T/logs"
mkdir -p "$WORK" "$LOGS"
if [ -n "${REUSE:-}" ]; then
  [ -d "$REUSE/store/data/migration" ] || { echo "REUSE=$REUSE has no migrated store" >&2; exit 2; }
  cp -R "$REUSE/store" "$STORE"
else
  cp -R "$REPO/tests/files-only/store-before" "$STORE"
fi
# "Install" the runtime into the synthetic store exactly as the installers do
for f in distill-process.md distill-monitor.md; do
  sed "s|{DISTILL_DIR}|$STORE|g" "$REPO/$f" > "$STORE/$f"
done
mkdir -p "$STORE/bin" "$STORE/data" "$STORE/inbox"
cp "$REPO/bin/distill-check-store.sh" "$STORE/bin/"; chmod +x "$STORE/bin/distill-check-store.sh"
echo enabled > "$STORE/.lifecycle"
[ -n "${REUSE:-}" ] || echo "idle $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STORE/.status"
echo "work dir: $T"

SANDBOX=()
if command -v sandbox-exec >/dev/null 2>&1; then
  deny=""
  for d in "$HOME/.aura-distill" "$HOME/.claude/distill" "$HOME/.claude/rules" "$HOME/.claude/CLAUDE.md" "$HOME/.codex" "$HOME/.gemini"; do
    deny="$deny(deny file-read* file-write* (subpath \"$d\"))"
  done
  SANDBOX=(sandbox-exec -p "(version 1)(allow default)$deny")
fi

# run_agent <name> <prompt> [extra claude args...]: one fresh session, stream-json transcript in $LOGS/<name>.jsonl
# SOURCES=project loads $WORK/CLAUDE.md (the Claude surface); the default loads no instruction file
run_agent() {
  local name=$1 prompt=$2; shift 2
  ( cd "$WORK" && env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_CHILD_SESSION \
      -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u AURA_DISTILL_HOME ENABLE_CLAUDEAI_MCP_SERVERS=false \
      ${SANDBOX[@]+"${SANDBOX[@]}"} claude -p "$prompt" --model "$MODEL" --setting-sources "${SOURCES:-local}" \
      --strict-mcp-config --mcp-config '{"mcpServers":{}}' --no-session-persistence \
      --dangerously-skip-permissions --disallowedTools WebFetch WebSearch --add-dir "$STORE" \
      --output-format stream-json --verbose "$@" < /dev/null > "$LOGS/$name.jsonl" 2> "$LOGS/$name.err" ) &
  local pid=$!
  ( sleep "$STEP_TIMEOUT"; kill "$pid" 2>/dev/null ) & local dog=$!
  wait "$pid"; local rc=$?
  kill "$dog" 2>/dev/null; wait "$dog" 2>/dev/null
  return $rc
}
# final <name>: the session's final answer text
final() { python3 - "$LOGS/$1.jsonl" <<'PY'
import json, sys
res = ""
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    try: ev = json.loads(line)
    except Exception: continue
    if ev.get("type") == "result": res = ev.get("result") or res
print(res)
PY
}
# reads <name>: "<assistant turn> <path>" for every Read tool call, plus the largest batch size
reads() { python3 - "$LOGS/$1.jsonl" "$STORE" <<'PY'
import json, sys
turn, batches, out = 0, [], []
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    try: ev = json.loads(line)
    except Exception: continue
    if ev.get("type") != "assistant": continue
    mid = ev.get("message", {}).get("id")
    for c in ev.get("message", {}).get("content", []):
        if c.get("type") == "tool_use" and c.get("name") == "Read":
            p = c.get("input", {}).get("file_path", "").replace(sys.argv[2] + "/", "")
            out.append((mid, p))
from collections import Counter
cnt = Counter(m for m, _ in out)
print("reads: " + ", ".join(p for _, p in out))
print("largest parallel read batch: %d" % (max(cnt.values()) if cnt else 0))
PY
}
tree_hash() { (cd "$STORE" && find . -type f ! -path './data/*' ! -name '.status' | LC_ALL=C sort | while IFS= read -r f; do shasum -a 256 "$f"; done) | shasum -a 256 | cut -d' ' -f1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

ISOLATION="This is an isolated test on a synthetic store. The knowledge directory is $STORE (it stands for {DISTILL_DIR}). Do not read or write anything outside $T. There is no user to ask: where the instructions say to ask or confirm, treat the request in this prompt as the answer."

if [ -z "${REUSE:-}" ]; then
echo "== A. migrate-store (model: $MODEL) =="
run_agent migrate-preview "You are the aura-distill distillation sub-agent. $ISOLATION
## Mode
migrate-store --preview
## Your process
Read $STORE/distill-process.md and follow it for this Mode. Return the preview report."
plan=$(ls -d "$STORE"/data/migration/*/PLAN.md 2>/dev/null | tail -1)
[ -n "$plan" ] && ok "preview wrote a plan ($(basename "$(dirname "$plan")"))" || bad "preview wrote no PLAN.md"
[ ! -f "$STORE/CATALOG.md" ] && [ -f "$STORE/projects/atlas.md" ] && ok "preview changed no knowledge file" || bad "preview changed the store"

run_agent migrate-apply "You are the aura-distill distillation sub-agent. $ISOLATION
The user reviewed the migration preview in ${plan:-data/migration/} and accepted it.
## Mode
migrate-store --apply
## Your process
Read $STORE/distill-process.md and follow it for this Mode. Return the report."
backup=$(ls -d "$STORE"/data/migration/*/backup 2>/dev/null | tail -1)
ls "$STORE"/data/migration/*/PENDING >/dev/null 2>&1 && bad "PENDING still present after apply" || ok "PENDING cleared"
ls "$STORE"/data/migration/*/DONE >/dev/null 2>&1 && ok "DONE written" || bad "no DONE marker"
if [ -n "$backup" ]; then
  out=$(bash "$REPO/bin/distill-check-store.sh" "$STORE" --before "$backup" 2>&1); rc=$?
  echo "$out" | sed 's/^/     /'
  [ $rc -eq 0 ] && ok "checker passes against the agent's own backup" || bad "checker fails against the agent's backup"
else bad "no backup directory"; fi
out=$(bash "$REPO/bin/distill-check-store.sh" "$STORE" --before "$REPO/tests/files-only/store-before" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "checker passes against the pristine fixture" || { bad "checker fails against the pristine fixture"; echo "$out" | sed 's/^/     /'; }
[ -f "$STORE/archive/projects/atlas.md" ] && [ ! -f "$STORE/projects/atlas.md" ] && ok "lifecycle archived the stale Atlas project" || bad "Atlas not archived"
[ -f "$STORE/archive/legacy/archive/projects/ember.md" ] && ok "unledgered archive adopted as legacy" || bad "ember not adopted"
[ -f "$STORE/projects/comet.md" ] && ok "pinned Comet stayed active" || bad "pinned Comet moved"
echo "     SPINE: $(wc -l < "$STORE/SPINE.md" | tr -d ' ') lines, $(wc -c < "$STORE/SPINE.md" | tr -d ' ') bytes (was 21 lines, 2576 bytes)"
else
  echo "== A. skipped: reusing the migrated store of $REUSE =="
fi

echo "== B. retrieval in fresh sessions (surface: $SURFACE) =="
# The integration text each client really gets, resolved to the synthetic store: the managed
# block comes from install.sh's own integration_block function (the shipped bytes, not a copy)
managed_block() { ( DISTILL_DIR=$STORE; MANAGED_START='<!-- aura-distill:start -->'; MANAGED_END='<!-- aura-distill:end -->'
  eval "$(sed -n '/^integration_block() {/,/^}/p' "$REPO/install.sh")"; integration_block "$1" ); }
if [ "$SURFACE" = claude ]; then
  { managed_block claude; printf '\n'; sed "s|{DISTILL_DIR}|$STORE|g" "$REPO/rules/distill.md"; } > "$WORK/CLAUDE.md"
  SURFACE_ARGS=(); export SOURCES=project
else
  SURFACE_ARGS=(--append-system-prompt "$(managed_block codex)"); export SOURCES=local
fi
before=$(tree_hash)
# ask <name> <question> <regex>...: every regex must match the answer (case-insensitive, extended)
ask() {
  local name=$1 q=$2; shift 2
  run_agent "$name" "$q" ${SURFACE_ARGS[@]+"${SURFACE_ARGS[@]}"}
  local ans; ans=$(final "$name")
  printf '%s\n' "$ans" > "$LOGS/$name.answer.txt"
  local miss=""
  for re in "$@"; do printf '%s' "$ans" | tr '\n' ' ' | grep -Eiq -- "$re" || miss="$miss [$re]"; done
  echo "     Q: $q"; reads "$name" | sed 's/^/     /'
  echo "     A: $(printf '%s' "$ans" | tr '\n' ' ' | cut -c1-400)"
  [ -z "$miss" ] && ok "$name" || bad "$name (missing:$miss)"
}
ask q1-read-with "I'm about to shorten the staging soak for the Beacon service to 10 minutes so we ship faster. OK to go ahead?" \
  "30 ?min" "(directive|platform lead)"
ask q2-protected "I'm writing a fixture for the new billing tests using my colleague Laura's real account data. Anything I should know first?" \
  "(generic|persona)" "(never|not|don.t|do not).{0,80}(real|colleague)"
ask q3-archived "What did we decide about partitioning for the Atlas lakehouse tables, and why?" \
  "ingest_date" "archiv"
ask q4-scoped-miss "What did we decide last time about the Kafka consumer group naming for the Orion service?" \
  "(not proof|catalog)" "Orion"
ask q5-pinned "How long do we keep invoice records for Comet, and can I delete old ones?" \
  "10 ?(years|yr)" "tombstone"
after=$(tree_hash)
[ "$before" = "$after" ] && ok "retrieval left the store byte-identical (archives read-only)" || bad "retrieval changed the store"

echo
unset SOURCES
echo "fresh-agent validation ($MODEL, $SURFACE surface): $PASS passed, $FAIL failed"
echo "transcripts and answers: $LOGS"
[ "${KEEP:-1}" = 1 ] || rm -rf "$T"
[ $FAIL -eq 0 ]
