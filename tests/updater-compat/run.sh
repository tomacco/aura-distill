#!/usr/bin/env bash
# Legacy updater compatibility reproductions (issue #76, ADR docs/adr/0001).
#
# What this proves, without the network and without touching any real profile:
#   (a) an old client executing the SHIPPED update instructions against the fixed
#       main URLs installs whatever main serves; a consent gate that exists only in
#       the newer updater text cannot protect it, because the gate arrives inside
#       the payload it was meant to guard;
#   (b) the decided channel strategy (main root stays the files-only line forever,
#       software major published on a separate channel that no shipped updater
#       references) keeps every such client on the files-only line;
#   (c) stale/mixed cache responses cannot produce a software payload either, so
#       safety never depends on .version or on the client having received a
#       newer updater;
#   (d) the consent boundary refuses non-interactive input: no terminal, piped
#       "yes", or empty input all mean "stay on files-only", nothing written.
#
# Fixtures: tests/updater-compat/fixtures/updaters/*.sh are the curl blocks as they
# shipped (see each header for the commit). fixtures/endpoints/<scenario>/ is served
# over a local HTTP server on 127.0.0.1 laid out like raw.githubusercontent.com
# (/tomacco/<repo>/<branch>/<file>). The only rewrite applied to a captured block is
# the host (raw.githubusercontent.com -> 127.0.0.1:PORT), {DISTILL_DIR} (resolved at
# install time by install.sh) and NEW_VERSION (substituted by the agent from the
# fetched VERSION). If no Python is available, an exported curl() shim resolves the
# same URLs to the same files and logs the same request lines.
#
# Usage: bash tests/updater-compat/run.sh
#        AURA_UPDATER_COMPAT_SHIM=1 bash tests/updater-compat/run.sh   (force the curl shim)
set -euo pipefail
cd "$(dirname "$0")"
HERE=$(pwd)
REPO_ROOT=$(cd ../.. && pwd)
MARKER='AURA_SOFTWARE_MAJOR_PAYLOAD'

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
check() { local desc=$1; shift; if "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi; }
section() { printf '\n== %s\n' "$1"; }

WORK=$(mktemp -d)
SERVE="$WORK/serve"
ACCESS_LOG="$WORK/access.log"
SERVER_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || taskkill //F //PID "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$SERVE"
: > "$ACCESS_LOG"

# ---------- local endpoint ----------
PY=""
for candidate in python3 python; do
  if "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 7) else 1)' >/dev/null 2>&1; then
    PY=$candidate; break
  fi
done
[ -n "${AURA_UPDATER_COMPAT_SHIM:-}" ] && PY=""

if [ -n "$PY" ]; then
  PORT=$("$PY" -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
  SERVE_NATIVE=$(cygpath -w "$SERVE" 2>/dev/null || printf '%s' "$SERVE")
  "$PY" -m http.server "$PORT" --bind 127.0.0.1 --directory "$SERVE_NATIVE" >"$ACCESS_LOG" 2>&1 &
  SERVER_PID=$!
  BASE="http://127.0.0.1:$PORT"
  for _ in $(seq 1 50); do
    curl -fs "$BASE/" >/dev/null 2>&1 && break
    sleep 0.1
  done
  curl -fs "$BASE/" >/dev/null 2>&1 || { echo "local HTTP server did not start"; exit 1; }
  ENDPOINT_MODE="python http.server on $BASE"
else
  # Shim: same URLs, same files, same log line shape. Exported so `bash script`
  # children see it. Only the flags the captured blocks use are handled.
  BASE="http://127.0.0.1:0"
  curl() {
    local out="" url="" fail_on_404=0 a
    while [ $# -gt 0 ]; do
      a=$1; shift
      case "$a" in
        -o) out=$1; shift ;;
        http*) url=$a ;;
        -*f*) fail_on_404=1 ;;
        -*) ;;
        *) ;;
      esac
    done
    local path=${url#"$AURA_TEST_BASE"}
    printf '127.0.0.1 - - [shim] "GET %s HTTP/1.1"\n' "$path" >> "$AURA_TEST_LOG"
    if [ -f "$AURA_TEST_SERVE$path" ]; then
      if [ -n "$out" ]; then cat "$AURA_TEST_SERVE$path" > "$out"; else cat "$AURA_TEST_SERVE$path"; fi
    else
      [ "$fail_on_404" = 1 ] && return 22
      if [ -n "$out" ]; then printf '404: Not Found' > "$out"; else printf '404: Not Found'; fi
    fi
  }
  export AURA_TEST_BASE="$BASE" AURA_TEST_LOG="$ACCESS_LOG" AURA_TEST_SERVE="$SERVE"
  export -f curl
  ENDPOINT_MODE="curl shim (no python found)"
fi

serve_scenario() { # <endpoint fixture dir name>
  rm -rf "$SERVE/tomacco"
  mkdir -p "$SERVE/tomacco/aura-distill" "$SERVE/tomacco/claude-distill"
  cp -R "$HERE/fixtures/endpoints/$1/." "$SERVE/tomacco/aura-distill/"
  # The pre-rename repo path still serves the same tree (checked live 2026-09-11:
  # HTTP 200 for tomacco/claude-distill/main/VERSION). Mirror that here.
  cp -R "$HERE/fixtures/endpoints/$1/." "$SERVE/tomacco/claude-distill/"
}

requests_to() { grep -c "GET $1" "$ACCESS_LOG" 2>/dev/null || true; }

# ---------- clients ----------
# A client = a sandbox HOME with an installed dispatcher, store, .version and the
# auto-update preference ON (the silent path in the shipped flow).
mkdir -p "$WORK/clients"
new_client() { # <installed-version> <layout: legacy|shared>  -> prints HOME
  local home store
  home=$(mktemp -d -p "$WORK/clients")
  if [ "$2" = legacy ]; then store="$home/.claude/distill"; else store="$home/.aura-distill"; fi
  mkdir -p "$home/.claude/commands" "$store/feedback"
  printf '%s\n' "$1" > "$store/.version"
  local f
  for f in "$home/.claude/commands/distill.md" "$store/distill-process.md" "$store/distill-monitor.md"; do
    printf 'installed file (synthetic)\nAURA_FIXTURE_LINE: files-only\nAURA_FIXTURE_PAYLOAD: installed-%s\n' "$1" > "$f"
  done
  printf -- '---\ndomain: feedback\nscope: distill system preferences\n---\n\n## Auto-update\n- enabled: true\n' > "$store/feedback/preferences.md"
  printf '%s' "$home"
}
store_of() { if [ -d "$1/.aura-distill" ]; then printf '%s' "$1/.aura-distill"; else printf '%s' "$1/.claude/distill"; fi; }

# Execute the shipped dispatcher flow for one client: fetch main/VERSION (step 3),
# compare with .version (step 4), and on mismatch run the captured block verbatim
# (auto-update ON, so no question is asked). Prints "updated" or "no-update".
run_dispatcher() { # <fixture> <client home>
  local fixture=$1 home=$2 store repo latest installed script
  store=$(store_of "$home")
  repo=$(grep -o 'tomacco/[a-z-]*' "$fixture" | head -1)
  latest=$(curl -sL "$BASE/$repo/main/VERSION" | tr -d '[:space:]')
  installed=$(tr -d '[:space:]' < "$store/.version")
  if [ "$latest" = "$installed" ]; then printf 'no-update'; return 0; fi
  script=$(mktemp -p "$WORK")
  {
    echo 'set -u'
    grep -v '^#' "$fixture" \
      | sed -e "s|https://raw.githubusercontent.com|$BASE|g" \
            -e "s|{DISTILL_DIR}|$store|g" \
            -e "s|NEW_VERSION|$latest|g"
  } > "$script"
  HOME="$home" bash "$script"
  printf 'updated'
}

# Execute the captured v1.0.0 installer fetch block (the Homebrew path) into a sandbox.
run_installer_v1_fetch() { # <client home>
  local home=$1 script
  script=$(mktemp -p "$WORK")
  mkdir -p "$home/.claude/commands" "$home/.claude/distill" "$home/.claude/rules"
  {
    echo 'set -u'
    printf 'CMD_DIR=%q\nDISTILL_DIR=%q\nRULES_DIR=%q\n' "$home/.claude/commands" "$home/.claude/distill" "$home/.claude/rules"
    grep -v '^#' "$HERE/fixtures/updaters/installer-v1.0.0-fetch.sh" \
      | sed -e "s|https://raw.githubusercontent.com|$BASE|g"
  } > "$script"
  HOME="$home" bash "$script"
}

# Execute the CURRENT install.sh from this checkout against the served endpoint.
run_current_installer() { # <client home>
  local home=$1
  mkdir -p "$home"
  HOME="$home" AURA_DISTILL_REPO="$BASE/tomacco/aura-distill/main" DISTILL_TOKEN_SAVER=off \
    bash "$REPO_ROOT/install.sh" </dev/null >/dev/null 2>&1
}

has_marker()  { grep -q "$MARKER" "$1"; }
no_marker_under() { ! grep -rq "$MARKER" "$1"; }
line_of()     { sed -n 's/^AURA_FIXTURE_LINE: //p' "$1" | head -1; }
version_of()  { tr -d '[:space:]' < "$1/.version"; }

printf 'updater-compat reproductions\n  endpoint: %s\n  sandbox:  %s\n' "$ENDPOINT_MODE" "$WORK"

# =====================================================================
section "0. Control: the harness performs a real update on the files-only line"
serve_scenario files-only-1.1.17
c=$(new_client 1.1.10 shared); s=$(store_of "$c")
r=$(run_dispatcher fixtures/updaters/dispatcher-v1.0.0.sh "$c")
check "v1.1.10 client (1.0.0-era block) updates when main/VERSION differs" test "$r" = updated
check "  .version now 1.1.17" test "$(version_of "$s")" = 1.1.17
check "  dispatcher, process, monitor overwritten from main" \
  test "$(line_of "$c/.claude/commands/distill.md")" = files-only -a \
       "$(sed -n 's/^AURA_FIXTURE_PAYLOAD: //p' "$s/distill-process.md")" = process-1.1.17
c=$(new_client 1.1.17 shared)
r=$(run_dispatcher fixtures/updaters/dispatcher-v1.1.17.sh "$c")
check "v1.1.17 client sees matching VERSION and does nothing" test "$r" = no-update

# =====================================================================
section "(a) Hypothesis under test: software major published at the historical main URLs"
serve_scenario unsafe-major-on-main
i=0
for spec in "dispatcher-v0.3.1.sh 0.3.1 legacy" "dispatcher-v1.0.0.sh 1.0.1 legacy" "dispatcher-v1.1.17.sh 1.1.17 shared"; do
  set -- $spec
  c=$(new_client "$2" "$3"); s=$(store_of "$c")
  r=$(run_dispatcher "fixtures/updaters/$1" "$c")
  check "$1 client at $2 ran the shipped block ($r)" test "$r" = updated
  check "  REPRODUCED: .version is now $(version_of "$s") and the dispatcher on disk is the software payload" \
    test "$(version_of "$s")" = 2.0.0 -a "$(line_of "$c/.claude/commands/distill.md")" = software-major
  check "  REPRODUCED: process and monitor are software payloads too" \
    bash -c "grep -q '$MARKER' '$s/distill-process.md' && grep -q '$MARKER' '$s/distill-monitor.md'"
  check "  the consent gate text arrived INSIDE the payload; no consent was ever recorded" \
    bash -c "grep -q '^GATE:' '$c/.claude/commands/distill.md' && [ ! -e '$s/.major-consent' ]"
done
# oldest client used the pre-rename repo path
check "v0.3.1 client fetched via the pre-rename tomacco/claude-distill path (redirect still live)" \
  test "$(requests_to /tomacco/claude-distill/main/distill.md)" -ge 1

c=$(new_client 1.0.1 legacy)
run_installer_v1_fetch "$c"
check "Homebrew path (v1.0.0 install.sh fetch block, hardcoded main) installs the software payload incl. rules/distill.md" \
  bash -c "grep -q '$MARKER' '$c/.claude/commands/distill.md' && grep -q '$MARKER' '$c/.claude/rules/distill.md'"

c=$(new_client 1.1.17 shared)
if run_current_installer "$c"; then
  check "current install.sh (curl|bash from main, AURA_DISTILL_REPO=main) installs the software payload with no gate" \
    bash -c "grep -q '$MARKER' '$c/.claude/commands/distill.md' && grep -q '$MARKER' '$c/.aura-distill/distill-process.md' && grep -q '$MARKER' '$c/.claude/rules/distill.md'"
else
  fail "current install.sh did not complete in the sandbox (see $WORK)"
fi

# =====================================================================
section "(b) Decided strategy: main root stays files-only; software major on its own channel"
serve_scenario channel-strategy
: > "$ACCESS_LOG"
check "software payload really exists on the channel (served tree, not fetched)" \
  has_marker "$SERVE/tomacco/aura-distill/software-2.x/distill.md"
for spec in "dispatcher-v0.3.1.sh 0.3.1 legacy" "dispatcher-v1.0.0.sh 1.0.1 legacy" "dispatcher-v1.1.17.sh 1.1.17 shared"; do
  set -- $spec
  c=$(new_client "$2" "$3"); s=$(store_of "$c")
  r=$(run_dispatcher "fixtures/updaters/$1" "$c")
  check "$1 client at $2 updated ($r) to $(version_of "$s") and stayed on the files-only line" \
    test "$r" = updated -a "$(version_of "$s")" = 1.2.0 -a "$(line_of "$c/.claude/commands/distill.md")" = files-only
  check "  no software payload anywhere under the client home" no_marker_under "$c"
done
c=$(new_client 1.0.1 legacy)
run_installer_v1_fetch "$c"
check "Homebrew path (v1.0.0 fetch block) gets the files-only bridge, incl. rules" \
  bash -c "[ \"\$(sed -n 's/^AURA_FIXTURE_PAYLOAD: //p' '$c/.claude/rules/distill.md')\" = rules-1.2.0-bridge ]"
check "  no software payload under the client home" no_marker_under "$c"
c=$(new_client 1.1.17 shared)
if run_current_installer "$c"; then
  check "current install.sh gets the files-only bridge (dispatcher, process, monitor, rules, agents)" \
    bash -c "[ \"\$(sed -n 's/^AURA_FIXTURE_PAYLOAD: //p' '$c/.claude/commands/distill.md')\" = dispatcher-1.2.0-bridge ] && grep -q 'files-only' '$c/.claude/agents/scribe.md'"
  check "  no software payload under the client home" no_marker_under "$c"
else
  fail "current install.sh did not complete in the sandbox (see $WORK)"
fi
check "no request from any client or installer ever touched the software channel" \
  test "$(requests_to /tomacco/aura-distill/software-2.x/)" = 0
check "no request touched the channel via the pre-rename repo path either" \
  test "$(requests_to /tomacco/claude-distill/software-2.x/)" = 0
check "the channel manifest on main is inert for old clients: never requested by any shipped block" \
  test "$(requests_to /tomacco/aura-distill/main/channels/manifest.json)" = 0

# =====================================================================
section "(c) Stale / mixed cache responses (raw serves Cache-Control: max-age=300 per file)"
# Fresh VERSION, cached older files: client records a version it does not have.
serve_scenario channel-strategy
printf '1.3.0\n' > "$SERVE/tomacco/aura-distill/main/VERSION"
c=$(new_client 1.1.17 shared); s=$(store_of "$c")
r=$(run_dispatcher fixtures/updaters/dispatcher-v1.1.17.sh "$c")
check "VERSION ahead of files: client writes .version=$(version_of "$s") while holding $(sed -n 's/^AURA_FIXTURE_PAYLOAD: //p' "$s/distill-process.md")" \
  test "$(version_of "$s")" = 1.3.0 -a "$(sed -n 's/^AURA_FIXTURE_PAYLOAD: //p' "$s/distill-process.md")" = process-1.2.0-bridge
r=$(run_dispatcher fixtures/updaters/dispatcher-v1.1.17.sh "$c")
check "  next session: no-update (client is stuck on the older files until the next bump), still files-only" \
  test "$r" = no-update -a "$(line_of "$c/.claude/commands/distill.md")" = files-only
# Stale VERSION, fresh files: nothing happens at all.
serve_scenario channel-strategy
printf '1.1.17\n' > "$SERVE/tomacco/aura-distill/main/VERSION"
c=$(new_client 1.1.17 shared); s=$(store_of "$c")
r=$(run_dispatcher fixtures/updaters/dispatcher-v1.1.17.sh "$c")
check "VERSION behind files: no-update, installed files untouched" \
  test "$r" = no-update -a "$(sed -n 's/^AURA_FIXTURE_PAYLOAD: //p' "$s/distill-process.md")" = installed-1.1.17
# A wrong VERSION bump alone (major number leaks to main/VERSION, files still files-only)
serve_scenario channel-strategy
printf '2.0.0\n' > "$SERVE/tomacco/aura-distill/main/VERSION"
c=$(new_client 1.1.17 shared); s=$(store_of "$c")
r=$(run_dispatcher fixtures/updaters/dispatcher-v1.1.17.sh "$c")
check "main/VERSION mistakenly reads 2.0.0 with files-only files: .version lies (2.0.0) but no software payload on disk" \
  test "$(version_of "$s")" = 2.0.0 -a "$(line_of "$c/.claude/commands/distill.md")" = files-only
check "  therefore .version must never be the input to any channel or consent decision" no_marker_under "$c"

# =====================================================================
section "(d) Consent boundary: non-interactive input is never consent"
gate="$HERE/fixtures/consent-gate.sh"
g=$(mktemp -d -p "$WORK")
set +e
bash "$gate" 2.0.0 "start a local service; migrate the store" "https://example.invalid/guide" "$g/store" </dev/null >"$g/out1" 2>&1; rc1=$?
printf 'adopt 2.0.0\n' | bash "$gate" 2.0.0 "start a local service" "https://example.invalid/guide" "$g/store" >"$g/out2" 2>&1; rc2=$?
printf 'yes\n' | bash "$gate" 2.0.0 "start a local service" "https://example.invalid/guide" "$g/store" >"$g/out3" 2>&1; rc3=$?
set -e
check "no terminal (stdin closed): exit 2, nothing written" test "$rc1" = 2 -a ! -e "$g/store/.major-consent"
check "piped 'adopt 2.0.0' is not a terminal: exit 2, nothing written" test "$rc2" = 2 -a ! -e "$g/store/.major-consent"
check "piped 'yes': exit 2, nothing written" test "$rc3" = 2 -a ! -e "$g/store/.major-consent"
check "notice names the version, the side effects and the guide before refusing" \
  bash -c "grep -q 'v2.0.0' '$g/out1' && grep -q 'start a local service' '$g/out1' && grep -q 'example.invalid/guide' '$g/out1' && grep -q 'Kept files-only' '$g/out1'"

# =====================================================================
printf '\nRESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
