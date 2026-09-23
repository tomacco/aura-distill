#!/usr/bin/env bash
# The Windows update path end to end (#79): install with install.ps1 (PowerShell),
# then run the installed bin/distill-update.sh under bash, as /distill does from
# Claude Code on Windows (Git Bash). Runs in CI on windows-latest; also runs anywhere
# pwsh and bash exist (the Git Bash path assertions apply only where cygpath exists).
# Sandbox only: a temp home and a local raw-root fixture; no network, no real profile.
#
# Usage: bash tests/updater-compat/windows-smoke.sh   (PWSH=/path/to/pwsh to override)
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PWSH=${PWSH:-pwsh}
PASS=0; FAIL=0
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  PASS  $d"; else FAIL=$((FAIL+1)); echo "  FAIL  $d"; fi; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
mixed()  { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
home="$T/home"; raw="$T/raw"; mkdir -p "$home" "$raw/main"
for f in VERSION distill.md distill-process.md distill-monitor.md rules/distill.md agents/scribe.md agents/scout.md bin/distill-update.sh channels/manifest.json; do
  mkdir -p "$raw/main/$(dirname "$f")"; cp "$REPO_ROOT/$f" "$raw/main/$f"
done
printf '1.1.90\n' > "$raw/main/VERSION"

env -u AURA_DISTILL_HOME -u CODEX_HOME -u AURA_DISTILL_RAW_ROOT -u DISTILL_CHANNEL \
  USERPROFILE="$(native "$home")" HOME="$home" AURA_DISTILL_HOME="$(native "$home/.aura-distill")" \
  CODEX_HOME="$(native "$home/.codex")" AURA_DISTILL_REPO="$(native "$raw/main")" DISTILL_TOKEN_SAVER=off \
  "$PWSH" -NoProfile -File "$(native "$REPO_ROOT/install.ps1")" >"$T/install.log" 2>&1 || { cat "$T/install.log"; exit 1; }
store="$home/.aura-distill"
check "install.ps1 installed the updater, v1.1.90, stable channel" \
  bash -c "[ -f '$store/bin/distill-update.sh' ] && [ \"\$(cat '$store/.version')\" = 1.1.90 ] && [ \"\$(cat '$store/.channel')\" = stable ]"

printf '1.1.91\n' > "$raw/main/VERSION"; printf '\nWINDOWS-SMOKE-PATCH\n' >> "$raw/main/distill-process.md"
HOME="$home" AURA_DISTILL_RAW_ROOT="$(mixed "$raw")" bash "$store/bin/distill-update.sh" apply >"$T/update.out" 2>"$T/update.err" || true
echo "  updater: $(head -1 "$T/update.out")"
check "the updater run by bash applies the update written for this store" \
  bash -c "grep -q '^UPDATED 1.1.90 1.1.91 stable' '$T/update.out' && grep -q WINDOWS-SMOKE-PATCH '$store/distill-process.md' && [ \"\$(cat '$store/.version')\" = 1.1.91 ]"
cmd="$home/.claude/commands/distill.md"
check "the dispatcher recorded by install.ps1 (.command-path) is the one updated" \
  bash -c "grep -qF '$(mixed "$store")/bin/distill-update.sh' '$cmd'"
if command -v cygpath >/dev/null 2>&1; then
  check "Git Bash: installed files carry C:/ paths, never the MSYS /c/ form" \
    bash -c "! grep -qF '$(cygpath -u "$store")/' '$cmd' '$store/distill-process.md' '$store/distill-monitor.md'"
fi
check "no stderr from the updater" test ! -s "$T/update.err"
printf 'windows-smoke: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
