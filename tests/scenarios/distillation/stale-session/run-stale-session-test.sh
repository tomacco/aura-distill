#!/bin/bash
# Stale-session test (#140): an old session distilled last must not overwrite newer knowledge.
# Runs one distillation agent against a mktemp store, then asserts the result with check.sh.
# The default agent is isolated from the real profile: --bare skips CLAUDE.md, hooks and the
# keychain (so it needs ANTHROPIC_API_KEY), no session is saved, it runs inside the store, and
# HOME points at an empty directory so a read of ~/.claude or ~/.aura-distill finds nothing real.
# DISTILL_AGENT_CMD overrides the agent; it receives the prompt as its last argument and must be
# just as isolated (never the real ~/.claude or ~/.aura-distill).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
STORE="$(mktemp -d)"
"$DIR/setup.sh" "$STORE" >/dev/null
REPORT="$STORE/report.md"
AGENT="${DISTILL_AGENT_CMD:-claude --bare -p --no-session-persistence --dangerously-skip-permissions --add-dir $STORE}"

mkdir "$STORE/home"
(cd "$STORE" && DISTILL_DIR="$STORE" HOME="$STORE/home" $AGENT "$(cat prompt.md)") > "$REPORT" 2>&1 || true
rc=0
"$DIR/check.sh" "$STORE" "$REPORT" || rc=$?
echo "store: $STORE"
exit $rc
