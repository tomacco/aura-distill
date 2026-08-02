#!/bin/bash
set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
INSTALLER="${2:-$REPO_ROOT/install.sh}"
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.claude/distill/craft"
cat > "$TEST_HOME/.claude/CLAUDE.md" <<'EOF'
# Distill — knowledge system (github.com/tomacco/aura-distill)

partial legacy block with no gate

# My important section
DO-NOT-DELETE
EOF
printf '# Legacy SPINE\n' > "$TEST_HOME/.claude/distill/SPINE.md"
printf 'LEGACY-KNOWLEDGE\n' > "$TEST_HOME/.claude/distill/craft/legacy.md"

run_install() {
  if [ -n "${AURA_INSTALL_SCRIPT_B64:-}" ]; then
    HOME="$TEST_HOME" AURA_DISTILL_REPO="$REPO_ROOT" DISTILL_TOKEN_SAVER=off \
      bash -c "$(printf '%s' "$AURA_INSTALL_SCRIPT_B64" | base64 -d)" </dev/null >/dev/null
  else
    HOME="$TEST_HOME" AURA_DISTILL_REPO="$REPO_ROOT" DISTILL_TOKEN_SAVER=off \
      bash "$INSTALLER" </dev/null >/dev/null
  fi
}

run_install

test -f "$TEST_HOME/.aura-distill/SPINE.md"
test -f "$TEST_HOME/.codex/AGENTS.md"
grep -q 'DO-NOT-DELETE' "$TEST_HOME/.claude/CLAUDE.md"
grep -q 'LEGACY-KNOWLEDGE' "$TEST_HOME/.aura-distill/craft/legacy.md"

# Distillation ledger (#46): data/ dir exists and the installed dispatcher
# carries the ledger instructions with {DISTILL_DIR} resolved
test -d "$TEST_HOME/.aura-distill/data"
grep -q 'distill-ledger.jsonl' "$TEST_HOME/.claude/commands/distill.md"
grep -q 'aura-distill-beacon' "$TEST_HOME/.claude/commands/distill.md"
if grep -q '{DISTILL_DIR}' "$TEST_HOME/.claude/commands/distill.md"; then
  echo "FAIL unresolved {DISTILL_DIR} placeholder in installed distill.md" >&2
  exit 1
fi

before_claude=$(sha256sum "$TEST_HOME/.claude/CLAUDE.md")
before_codex=$(sha256sum "$TEST_HOME/.codex/AGENTS.md")
run_install
after_claude=$(sha256sum "$TEST_HOME/.claude/CLAUDE.md")
after_codex=$(sha256sum "$TEST_HOME/.codex/AGENTS.md")

test "$before_claude" = "$after_claude"
test "$before_codex" = "$after_codex"

printf 'PASS bash installer preserves partial legacy content and is byte-stable\n'
