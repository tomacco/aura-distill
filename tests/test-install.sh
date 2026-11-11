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

# Run lock: both twins installed into the shared store, the bash one executable
test -x "$TEST_HOME/.aura-distill/bin/distill-lock.sh"
test -f "$TEST_HOME/.aura-distill/bin/distill-lock.ps1"
grep -q 'bin/distill-lock.sh acquire' "$TEST_HOME/.claude/commands/distill.md"
DISTILL_DIR= "$TEST_HOME/.aura-distill/bin/distill-lock.sh" status | grep -qx 'free'

# INBOX (#47): inbox/ dir exists; consume instructions in the process engine;
# explicit-save instructions in the monitor and the always-on rules file
test -d "$TEST_HOME/.aura-distill/inbox"
grep -q 'Step 0b: Consume the INBOX' "$TEST_HOME/.aura-distill/distill-process.md"
grep -q 'user-explicit' "$TEST_HOME/.aura-distill/distill-monitor.md"
grep -q 'INBOX' "$TEST_HOME/.claude/rules/distill.md"

# settings.json (#153): the auto-memory key is added to any object layout, the result
# is valid JSON with every existing key kept, and a file that is not an object is
# left byte for byte with a warning instead of a success line.
settings_case() { # name, content, expect (added|untouched)
  local name="$1" content="$2" expect="$3" h out
  h=$(mktemp -d); mkdir -p "$h/.claude"
  printf '%s' "$content" > "$h/.claude/settings.json"
  out=$(HOME="$h" AURA_DISTILL_REPO="$REPO_ROOT" bash "$INSTALLER" --no-token-saver </dev/null 2>&1)
  if [ "$expect" = added ]; then
    python3 - "$h/.claude/settings.json" "$content" <<'PY' || { echo "FAIL settings.json case: $name" >&2; exit 1; }
import json, sys
new = json.load(open(sys.argv[1])); old = json.loads(sys.argv[2])
assert new.pop("autoMemoryEnabled") is False
assert new == old, (new, old)
PY
    printf '%s' "$out" | grep -q 'Disabled auto-memory' || { echo "FAIL no success line: $name" >&2; exit 1; }
  else
    test "$(cat "$h/.claude/settings.json")" = "$content" || { echo "FAIL settings.json changed: $name" >&2; exit 1; }
    if printf '%s' "$out" | grep -q 'Disabled auto-memory'; then echo "FAIL false success line: $name" >&2; exit 1; fi
    printf '%s' "$out" | grep -q 'left as it is' || { echo "FAIL no warning: $name" >&2; exit 1; }
  fi
  rm -rf "$h"
}
settings_case 'multi-line object' '{
  "model": "opus",
  "env": {"A": "1"}
}
' added
settings_case 'one-line object' '{"model":"opus"}' added
settings_case 'empty object on two lines' '{
}
' added
settings_case 'empty object on one line' '{}' added
settings_case 'indented, CRLF' "$(printf '  {\r\n  "a": [1, {"b": 2}]\r\n}\r\n')" added
settings_case 'not an object' '[1, 2]' untouched
settings_case 'empty file' '' untouched
printf 'PASS install.sh edits settings.json safely in every layout\n'

before_claude=$(sha256sum "$TEST_HOME/.claude/CLAUDE.md")
before_codex=$(sha256sum "$TEST_HOME/.codex/AGENTS.md")
run_install
after_claude=$(sha256sum "$TEST_HOME/.claude/CLAUDE.md")
after_codex=$(sha256sum "$TEST_HOME/.codex/AGENTS.md")

test "$before_claude" = "$after_claude"
test "$before_codex" = "$after_codex"

printf 'PASS bash installer preserves partial legacy content and is byte-stable\n'

# Failed download (#151): an upgrade that cannot fetch the core files exits nonzero
# and leaves every installed file as it was, byte for byte.
core_files="$TEST_HOME/.claude/commands/distill.md $TEST_HOME/.aura-distill/distill-process.md
$TEST_HOME/.aura-distill/distill-monitor.md $TEST_HOME/.aura-distill/bin/distill-lock.sh
$TEST_HOME/.aura-distill/bin/distill-lock.ps1"
before_core=$(sha256sum $core_files)
if HOME="$TEST_HOME" AURA_DISTILL_REPO="$TEST_HOME/no-such-repo" DISTILL_TOKEN_SAVER=off \
     bash "$INSTALLER" </dev/null >"$TEST_HOME/failed-install.out" 2>&1; then
  echo "FAIL install.sh exited 0 although no core file could be downloaded" >&2; exit 1
fi
test "$before_core" = "$(sha256sum $core_files)" \
  || { echo "FAIL a failed download changed installed core files" >&2; exit 1; }
grep -q 'Nothing was changed' "$TEST_HOME/failed-install.out"
# One missing file among good ones: nothing is replaced either (all-or-nothing).
PARTIAL_REPO="$TEST_HOME/partial-repo"; mkdir -p "$PARTIAL_REPO/bin"
cp "$REPO_ROOT/distill.md" "$PARTIAL_REPO/"; printf '# changed aura-distill\n' >> "$PARTIAL_REPO/distill.md"
if HOME="$TEST_HOME" AURA_DISTILL_REPO="$PARTIAL_REPO" DISTILL_TOKEN_SAVER=off \
     bash "$INSTALLER" </dev/null >/dev/null 2>&1; then
  echo "FAIL install.sh exited 0 with a partial repo" >&2; exit 1
fi
test "$before_core" = "$(sha256sum $core_files)" \
  || { echo "FAIL a partial download replaced some core files" >&2; exit 1; }
# A failed first install creates nothing, so "Nothing was changed" is true.
EMPTY_HOME=$(mktemp -d); mkdir -p "$EMPTY_HOME/.claude/distill"
printf 'LEGACY\n' > "$EMPTY_HOME/.claude/distill/SPINE.md"
if HOME="$EMPTY_HOME" AURA_DISTILL_REPO="$EMPTY_HOME/no-such-repo" bash "$INSTALLER" </dev/null >/dev/null 2>&1; then
  echo "FAIL a first install without a repo exited 0" >&2; exit 1
fi
test ! -e "$EMPTY_HOME/.aura-distill" && test ! -e "$EMPTY_HOME/.claude/commands" \
  || { echo "FAIL a failed first install left files behind" >&2; exit 1; }
# A symlinked command file is written through, not replaced by a regular file.
mkdir -p "$TEST_HOME/dotfiles"
mv "$TEST_HOME/.claude/commands/distill.md" "$TEST_HOME/dotfiles/distill.md"
ln -s "$TEST_HOME/dotfiles/distill.md" "$TEST_HOME/.claude/commands/distill.md"
: > "$TEST_HOME/dotfiles/distill.md"
run_install
test -L "$TEST_HOME/.claude/commands/distill.md" && test -s "$TEST_HOME/dotfiles/distill.md" \
  || { echo "FAIL install.sh replaced a symlinked command file" >&2; exit 1; }
rm "$TEST_HOME/.claude/commands/distill.md"; mv "$TEST_HOME/dotfiles/distill.md" "$TEST_HOME/.claude/commands/distill.md"
rm -rf "$EMPTY_HOME"
printf 'PASS install.sh leaves the install untouched when a download fails\n'

# Always-On preferences rule (same as install.ps1): the section from the heading to
# the end of the file is kept byte for byte unless it equals the shipped template
# ignoring whitespace; a file without the heading gets the release's file.
MARK="## Always-On User Preferences"
RULES="$TEST_HOME/.claude/rules/distill.md"
SECTION_FILE="$TEST_HOME/prefs-section"
prefs_case() { # name, expect (kept|replaced); section read from $SECTION_FILE or MISSING
  local name="$1" expect="$2" mode="${3:-}" body_tmp after_section
  body_tmp=$(mktemp)
  if [ "$mode" = MISSING ]; then
    printf 'OLD-FILE-WITHOUT-HEADING\n' > "$RULES"
  else
    sed "/^$MARK/,\$d" "$RULES" > "$body_tmp"
    cat "$body_tmp" "$SECTION_FILE" > "$RULES"
  fi
  rm -f "$body_tmp"
  run_install
  after_section=$(mktemp)
  sed -n "/^$MARK/,\$p" "$RULES" > "$after_section"
  if [ "$expect" = kept ]; then
    cmp -s "$after_section" "$SECTION_FILE" \
      || { echo "FAIL install.sh did not keep $name preferences byte for byte" >&2; exit 1; }
  else
    grep -q "^$MARK" "$RULES" && ! grep -q 'OLD-FILE-WITHOUT-HEADING' "$RULES" \
      && ! cmp -s "$after_section" "$SECTION_FILE" \
      || { echo "FAIL install.sh did not replace $name with the release's section" >&2; exit 1; }
  fi
  rm -f "$after_section"
  printf 'PASS install.sh %s preferences: %s\n' "$expect" "$name"
}
printf '%s\n\n- Answer in bullet points.\n- Never use emoji.\n' "$MARK" > "$SECTION_FILE"
prefs_case 'bullet-only' kept
printf '%s\n\nKeep answers short; ask before large refactors.\n' "$MARK" > "$SECTION_FILE"
prefs_case 'prose' kept
printf '%s\n\n- Responde en español, sin «adornos» ¿vale? — ûÿ\n' "$MARK" > "$SECTION_FILE"
prefs_case 'non-ASCII' kept
sed -n "/^$MARK/,\$p" "$REPO_ROOT/rules/distill.md" \
  | sed "s|{DISTILL_DIR}|$TEST_HOME/.aura-distill|g; s|\$|  |" > "$SECTION_FILE"
printf '\n\n' >> "$SECTION_FILE"
prefs_case 'an untouched template (whitespace differs)' replaced
prefs_case 'a file without the heading' replaced MISSING

# Legacy seed (#152): a legacy store is never copied over a shared store that holds
# knowledge. Second profile with an old distill/ directory, store without the marker.
SEED_HOME=$(mktemp -d)
mkdir -p "$SEED_HOME/.claude"
HOME="$SEED_HOME" AURA_DISTILL_REPO="$REPO_ROOT" bash "$INSTALLER" --no-token-saver </dev/null >/dev/null
test ! -e "$SEED_HOME/.aura-distill/.legacy-imported"
printf -- '- [Current](craft/a.md) - CURRENT-SPINE\n' >> "$SEED_HOME/.aura-distill/SPINE.md"
printf 'CURRENT-CARD\n' > "$SEED_HOME/.aura-distill/craft/a.md"
mkdir -p "$SEED_HOME/.claude-work/distill/craft"
printf 'OLD-SPINE\n' > "$SEED_HOME/.claude-work/distill/SPINE.md"
printf 'OLD-CARD\n' > "$SEED_HOME/.claude-work/distill/craft/a.md"
printf 'OLD-ONLY\n' > "$SEED_HOME/.claude-work/distill/craft/only-in-legacy.md"
HOME="$SEED_HOME" AURA_DISTILL_REPO="$REPO_ROOT" bash "$INSTALLER" --profile work --no-token-saver \
  </dev/null >"$SEED_HOME/out" 2>&1
grep -q 'CURRENT-SPINE' "$SEED_HOME/.aura-distill/SPINE.md" && ! grep -q 'OLD-SPINE' "$SEED_HOME/.aura-distill/SPINE.md" \
  || { echo "FAIL a legacy store overwrote the shared SPINE" >&2; exit 1; }
grep -qx 'CURRENT-CARD' "$SEED_HOME/.aura-distill/craft/a.md" \
  || { echo "FAIL a legacy store overwrote a shared card" >&2; exit 1; }
test ! -e "$SEED_HOME/.aura-distill/craft/only-in-legacy.md"
grep -qx 'OLD-SPINE' "$SEED_HOME/.claude-work/distill/SPINE.md"
grep -q 'was not imported' "$SEED_HOME/out"
rm -rf "$SEED_HOME"
printf 'PASS install.sh never seeds a legacy store over a populated shared store\n'

# A store that was installed but never distilled (template index, empty tiers) is not
# knowledge: a legacy directory found later is still imported.
FRESH_HOME=$(mktemp -d)
mkdir -p "$FRESH_HOME/.claude"
HOME="$FRESH_HOME" AURA_DISTILL_REPO="$REPO_ROOT" bash "$INSTALLER" --no-token-saver </dev/null >/dev/null
mkdir -p "$FRESH_HOME/.claude-work/distill/craft"
printf -- '- [Old](craft/legacy.md) - OLD-SPINE\n' > "$FRESH_HOME/.claude-work/distill/SPINE.md"
printf 'OLD-CARD\n' > "$FRESH_HOME/.claude-work/distill/craft/legacy.md"
HOME="$FRESH_HOME" AURA_DISTILL_REPO="$REPO_ROOT" bash "$INSTALLER" --profile work --no-token-saver </dev/null >/dev/null
grep -qx 'OLD-CARD' "$FRESH_HOME/.aura-distill/craft/legacy.md" \
  || { echo "FAIL a legacy store was not imported into a never-distilled shared store" >&2; exit 1; }
grep -q 'OLD-SPINE' "$FRESH_HOME/.aura-distill/SPINE.md"
test -f "$FRESH_HOME/.aura-distill/.legacy-imported"
rm -rf "$FRESH_HOME"
printf 'PASS install.sh imports a legacy store into a never-distilled shared store\n'

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

# Installer input (#154). Unknown options stop the run before anything is written.
OPT_HOME=$(mktemp -d); mkdir -p "$OPT_HOME/.claude"
if HOME="$OPT_HOME" AURA_DISTILL_REPO="$REPO_ROOT" bash "$INSTALLER" --no-tokensaver \
     </dev/null >"$OPT_HOME/out" 2>&1; then
  echo "FAIL install.sh accepted an unknown option" >&2; exit 1
fi
grep -q 'unknown option: --no-tokensaver' "$OPT_HOME/out"
test ! -e "$OPT_HOME/.aura-distill" && test ! -e "$OPT_HOME/.claude/agents"
if HOME="$OPT_HOME" AURA_DISTILL_REPO="$REPO_ROOT" bash "$INSTALLER" --profile </dev/null >/dev/null 2>&1; then
  echo "FAIL install.sh accepted --profile without a name" >&2; exit 1
fi
printf 'PASS install.sh rejects unknown options before writing anything\n'

# Two profiles, installer piped into bash (stdin is the script, as with curl | bash).
# With a terminal the choice is read from it; without one the run stops with the
# --profile hint and writes nothing.
PIPE_HOME=$(mktemp -d); mkdir -p "$PIPE_HOME/.claude" "$PIPE_HOME/.claude-work"
python3 - "$INSTALLER" "$PIPE_HOME" "$REPO_ROOT" <<'PY' || { echo "FAIL piped install could not read the profile choice from the terminal" >&2; exit 1; }
import os, pty, select, sys, time
installer, home, repo = sys.argv[1:4]
pid, fd = pty.fork()
if pid == 0:
    os.environ.update(HOME=home, AURA_DISTILL_REPO=repo)
    os.execvp("bash", ["bash", "-c", 'cat "$0" | bash -s -- --no-token-saver', installer])
seen, answered, deadline = b"", False, time.time() + 60
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.5)
    if r:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        seen += chunk
        if not answered and b"Choose profile" in seen:
            os.write(fd, b"2\n"); answered = True
    elif os.waitpid(pid, os.WNOHANG)[0]:
        break
status = 0
try:
    status = os.waitpid(pid, 0)[1]
except ChildProcessError:
    pass
sys.exit(0 if answered and os.path.isfile(os.path.join(home, ".claude-work", "commands", "distill.md")) else 1)
PY
test ! -e "$PIPE_HOME/.claude/commands/distill.md"
printf 'PASS piped install.sh reads the profile choice from the terminal\n'

NOTTY_HOME=$(mktemp -d); mkdir -p "$NOTTY_HOME/.claude" "$NOTTY_HOME/.claude-work"
# setsid in a forked child drops the controlling terminal, so /dev/tty cannot be opened.
if HOME="$NOTTY_HOME" AURA_DISTILL_REPO="$REPO_ROOT" perl -MPOSIX -e \
     'my $p = fork; if ($p) { waitpid($p, 0); exit($? >> 8) } setsid(); exec @ARGV or exit 127' \
     bash -c 'cat "$0" | bash' "$INSTALLER" >"$NOTTY_HOME/out" 2>&1 </dev/null; then
  echo "FAIL piped install.sh without a terminal did not stop at the profile choice" >&2; exit 1
fi
grep -q 'Run again with --profile' "$NOTTY_HOME/out"
grep -q 'work' "$NOTTY_HOME/out"
test ! -e "$NOTTY_HOME/.aura-distill"
rm -rf "$OPT_HOME" "$PIPE_HOME" "$NOTTY_HOME"
printf 'PASS piped install.sh without a terminal stops with the --profile hint\n'
