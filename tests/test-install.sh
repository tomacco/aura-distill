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

# Isolation: never inherit AURA_DISTILL_HOME / CODEX_HOME (or a channel choice) from
# the calling shell; the installer would otherwise write outside TEST_HOME.
ISOLATE="env -u AURA_DISTILL_HOME -u CODEX_HOME -u DISTILL_CHANNEL -u AURA_DISTILL_RAW_ROOT -u AURA_DISTILL_CHANNEL_MANIFEST"
run_install() {
  if [ -n "${AURA_INSTALL_SCRIPT_B64:-}" ]; then
    $ISOLATE HOME="$TEST_HOME" AURA_DISTILL_HOME="$TEST_HOME/.aura-distill" CODEX_HOME="$TEST_HOME/.codex" \
      AURA_DISTILL_REPO="$REPO_ROOT" \
      bash -c "$(printf '%s' "$AURA_INSTALL_SCRIPT_B64" | base64 -d)" </dev/null >/dev/null
  else
    $ISOLATE HOME="$TEST_HOME" AURA_DISTILL_HOME="$TEST_HOME/.aura-distill" CODEX_HOME="$TEST_HOME/.codex" \
      AURA_DISTILL_REPO="$REPO_ROOT" \
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

# INBOX (#47): inbox/ dir exists; consume instructions in the process engine;
# explicit-save instructions in the monitor and the always-on rules file
test -d "$TEST_HOME/.aura-distill/inbox"
grep -q 'Step 0b: Consume the INBOX' "$TEST_HOME/.aura-distill/distill-process.md"
grep -q 'user-explicit' "$TEST_HOME/.aura-distill/distill-monitor.md"
grep -q 'INBOX' "$TEST_HOME/.claude/rules/distill.md"

# Release channels (#79): a default install records the stable channel, the payload
# version and the command path, and places the updater script the dispatcher runs.
test "$(cat "$TEST_HOME/.aura-distill/.channel")" = stable
test "$(cat "$TEST_HOME/.aura-distill/.version")" = "$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"
test "$(cat "$TEST_HOME/.aura-distill/.command-path")" = "$TEST_HOME/.claude/commands/distill.md"
test -x "$TEST_HOME/.aura-distill/bin/distill-update.sh"
grep -q "$TEST_HOME/.aura-distill/bin/distill-update.sh\" auto" "$TEST_HOME/.claude/commands/distill.md"

before_claude=$(sha256sum "$TEST_HOME/.claude/CLAUDE.md")
before_codex=$(sha256sum "$TEST_HOME/.codex/AGENTS.md")
run_install
after_claude=$(sha256sum "$TEST_HOME/.claude/CLAUDE.md")
after_codex=$(sha256sum "$TEST_HOME/.codex/AGENTS.md")

test "$before_claude" = "$after_claude"
test "$before_codex" = "$after_codex"

printf 'PASS bash installer preserves partial legacy content and is byte-stable\n'

# Ledger beacon resolution (#46): exercise the documented grep pipeline shape
# against fixture transcripts — both the match case and the empty-glob case
# (a bare grep with no file operands would hang on stdin; </dev/null guards it).
beacon="aura-distill-beacon 20260802T000000Z-12345"
mkdir -p "$TEST_HOME/.claude/projects/fixture"
printf 'other line\n%s\n' "$beacon" > "$TEST_HOME/.claude/projects/fixture/session-abc.jsonl"
printf 'no beacon here\n' > "$TEST_HOME/.claude/projects/fixture/session-def.jsonl"

found=$(grep -l "$beacon" $(ls -t "$TEST_HOME"/.claude/projects/*/*.jsonl "$TEST_HOME"/.codex/sessions/*/*/*/*.jsonl 2>/dev/null | head -30) </dev/null 2>/dev/null | head -1)
test "$(basename "$found" .jsonl)" = "session-abc"

empty=$(grep -l "$beacon" $(ls -t "$TEST_HOME"/nonexistent/*/*.jsonl 2>/dev/null | head -30) </dev/null 2>/dev/null | head -1 || true)
test -z "$empty"

printf 'PASS ledger beacon grep resolves fixtures and survives empty transcript roots\n'

# Files-only runtime (#78): the optional self-check helper is installed and executable,
# the Codex block routes maintenance requests, and the lifecycle knob follows the
# token-saver contract (absent = off; flags persist; remove deletes the setting).
AURA="$TEST_HOME/.aura-distill"
test -x "$AURA/bin/distill-check-store.sh"
test "$(sed -n 2p "$AURA/bin/distill-check-store.sh")" = "# aura-distill-check-store invariants v1"
grep -q 'clean up (gc), restore or migrate the store' "$TEST_HOME/.codex/AGENTS.md"
grep -q 'Retrieval protocol' "$AURA/distill-monitor.md"
grep -q 'CATALOG.md' "$TEST_HOME/.claude/rules/distill.md"
test ! -e "$AURA/.lifecycle"
lc_install() {
  env -u AURA_DISTILL_HOME -u CODEX_HOME -u DISTILL_LIFECYCLE -u DISTILL_CHANNEL -u AURA_DISTILL_RAW_ROOT -u AURA_DISTILL_CHANNEL_MANIFEST HOME="$TEST_HOME" AURA_DISTILL_REPO="$REPO_ROOT" DISTILL_TOKEN_SAVER=off \
    "$@" </dev/null >/dev/null
}
lc_install bash "$INSTALLER" --lifecycle;          test "$(cat "$AURA/.lifecycle")" = enabled
lc_install bash "$INSTALLER";                      test "$(cat "$AURA/.lifecycle")" = enabled
lc_install bash "$INSTALLER" --no-lifecycle;       test "$(cat "$AURA/.lifecycle")" = disabled
lc_install env DISTILL_LIFECYCLE=on bash "$INSTALLER"; test "$(cat "$AURA/.lifecycle")" = enabled
lc_install env DISTILL_LIFECYCLE=OFF bash "$INSTALLER"; test "$(cat "$AURA/.lifecycle")" = disabled   # any case, like install.ps1
lc_install env DISTILL_LIFECYCLE=On bash "$INSTALLER"; test "$(cat "$AURA/.lifecycle")" = enabled
lc_install bash "$INSTALLER" --remove-lifecycle;   test ! -e "$AURA/.lifecycle"
# a .lifecycle written by Windows PowerShell 5.1 may start with a UTF-8 BOM; it still reads as enabled
printf '\357\273\277enabled' > "$AURA/.lifecycle"
env -u AURA_DISTILL_HOME -u CODEX_HOME -u DISTILL_LIFECYCLE -u DISTILL_CHANNEL -u AURA_DISTILL_RAW_ROOT -u AURA_DISTILL_CHANNEL_MANIFEST HOME="$TEST_HOME" \
  AURA_DISTILL_REPO="$REPO_ROOT" DISTILL_TOKEN_SAVER=off bash "$INSTALLER" </dev/null > "$TEST_HOME/lc.out" 2>&1
grep -q 'enabled — kept' "$TEST_HOME/lc.out"
rm -f "$AURA/.lifecycle"
# This home was seeded from a legacy (pre-1.2) store: its copied SPINE is preserved and no
# catalog is added, so it stays a store for migrate-store, and the helper reports it cleanly
test ! -e "$AURA/CATALOG.md"
set +e; out=$(bash "$AURA/bin/distill-check-store.sh" "$AURA" 2>&1); rc=$?; set -e
test "$rc" -eq 1
printf '%s\n' "$out" | grep -q '^C2 FAIL'
# A fresh install is born in the files-only layout: SPINE catalog line + an empty, stamped
# CATALOG.md, and the shipped checker passes on it (never "unmigrated")
FRESH_HOME=$(mktemp -d)
env -u AURA_DISTILL_HOME -u CODEX_HOME -u DISTILL_LIFECYCLE -u DISTILL_CHANNEL -u AURA_DISTILL_RAW_ROOT -u AURA_DISTILL_CHANNEL_MANIFEST \
  HOME="$FRESH_HOME" AURA_DISTILL_REPO="$REPO_ROOT" DISTILL_TOKEN_SAVER=off bash "$INSTALLER" </dev/null >/dev/null
FRESH="$FRESH_HOME/.aura-distill"
grep -q '^- \[Catalog\](CATALOG.md)' "$FRESH/SPINE.md"
grep -Eq 'rebuilt: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "$FRESH/CATALOG.md"
out=$(bash "$FRESH/bin/distill-check-store.sh" "$FRESH" 2>&1) || { printf '%s\n' "$out" >&2; echo "FAIL fresh store does not pass the checker" >&2; exit 1; }
before_cat=$(sha256sum "$FRESH/CATALOG.md")
env -u AURA_DISTILL_HOME -u CODEX_HOME -u DISTILL_LIFECYCLE -u DISTILL_CHANNEL -u AURA_DISTILL_RAW_ROOT -u AURA_DISTILL_CHANNEL_MANIFEST \
  HOME="$FRESH_HOME" AURA_DISTILL_REPO="$REPO_ROOT" DISTILL_TOKEN_SAVER=off bash "$INSTALLER" </dev/null >/dev/null
test "$before_cat" = "$(sha256sum "$FRESH/CATALOG.md")"   # reinstall never rewrites the catalog
rm -rf "$FRESH_HOME"

printf 'PASS files-only runtime: helper installed, Codex routing, lifecycle knob\n'
