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
#   (e) the REAL bridge (this checkout's dispatcher, updater and installer served
#       at main) with a synthetic software major announced: old clients adopt the
#       bridge, the updater prints the notice once and never touches the channel;
#   (f) the shipped updater (bin/distill-update.sh): auto-update on/off, pinned
#       files-only, mixed and failed responses leave every installed file intact;
#   (g) the beta channel: opt-in install from a pinned tag, beta auto-update follows
#       the beta manifest (never main), stable installs never request beta URLs,
#       opt-out back to stable;
#   (h) the installers' own consent boundary: fresh install, non-interactive
#       refusal, typed consent through a pty, failed downloads;
#   (i) the CI endpoint guard (check-endpoints.sh) and the major-release check fail
#       on each class of unsafe change.
#
# What this cannot prove: whether a model executing the bridge dispatcher prose obeys
# it. Sections (e)-(h) execute the scripts the prose delegates to and the one command
# block it contains; section (e) checks the prose statically. The safety argument
# does not rest on the prose: the legacy endpoints never serve a software payload,
# and the updater script refuses one.
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
# Isolation: install.sh honors AURA_DISTILL_HOME and CODEX_HOME. A developer shell
# that exports them would otherwise receive the sandbox writes. Point both at a
# canary inside the sandbox for the runner's own environment; every installer
# invocation below overrides them explicitly, and the canary must stay absent.
CANARY="$WORK/canary"
export AURA_DISTILL_HOME="$CANARY/aura-distill" CODEX_HOME="$CANARY/codex"
ACCESS_LOG="$WORK/access.log"
SERVER_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || taskkill //F //PID "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  [ -n "${KEEP_WORK:-}" ] || rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$SERVE" "$WORK/tmp"
: > "$ACCESS_LOG"
# Temp files made by the installers and the updater stay inside the sandbox too.
export TMPDIR="$WORK/tmp"

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
  home=$(mktemp -d "$WORK/clients/c.XXXXXX")
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
  script=$(mktemp "$WORK/exec.XXXXXX")
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
  script=$(mktemp "$WORK/exec.XXXXXX")
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
# Token Saver stays at its default (on) so the agent presets are fetched and asserted;
# install.sh takes flags, not the DISTILL_TOKEN_SAVER variable install.ps1 reads.
run_current_installer() { # <client home>
  local home=$1
  mkdir -p "$home"
  env -u AURA_DISTILL_HOME -u CODEX_HOME -u DISTILL_CHANNEL -u AURA_DISTILL_RAW_ROOT -u AURA_DISTILL_CHANNEL_MANIFEST \
    HOME="$home" AURA_DISTILL_HOME="$home/.aura-distill" CODEX_HOME="$home/.codex" \
    AURA_DISTILL_REPO="$BASE/tomacco/aura-distill/main" \
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
set +e; run_current_installer "$c"; rc=$?; set -e
# Before #79 the checked-in install.sh installed this payload with no gate (reproduced
# on PR #94). It now validates the staged payload first and refuses it. Installers
# that already shipped (row above) still install it: that is why the endpoints stay safe.
check "current install.sh refuses a software payload at main: exit $rc, installed files untouched" \
  bash -c "[ $rc -ne 0 ] && grep -q 'installed-1.1.17' '$c/.claude/commands/distill.md' && ! grep -rq '$MARKER' '$c'" 

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
check "positive control: the log recorded the files-only fetches made after truncation" \
  test "$(requests_to /tomacco/aura-distill/main/distill.md)" -ge 3 -a \
       "$(requests_to /tomacco/claude-distill/main/distill.md)" -ge 1
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
g=$(mktemp -d "$WORK/gate.XXXXXX")
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
# Accept path needs a real terminal: drive the gate through a pty where Python offers one.
if [ -n "$PY" ] && "$PY" -c 'import pty' >/dev/null 2>&1; then
  set +e
  "$PY" - "$gate" "$g/store-tty" >"$g/out4" 2>&1 <<'PYEOF'
import os, pty, sys
gate, store = sys.argv[1], sys.argv[2]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", gate, "2.0.0", "start a local service", "https://example.invalid/guide", store])
out, sent = b"", False
while True:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    out += chunk
    if not sent and b"keep files-only:" in out:
        os.write(fd, b"adopt 2.0.0\n"); sent = True
_, status = os.waitpid(pid, 0)
sys.stdout.write(out.decode(errors="replace"))
sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1)
PYEOF
  rc4=$?
  set -e
  check "terminal + typed 'adopt 2.0.0': exit 0 and consent recorded before any side effect" \
    test "$rc4" = 0 -a -f "$g/store-tty/.major-consent"
else
  printf '  SKIP  terminal accept path (needs Python with the pty module; absent in shim mode or on this platform)\n'
fi

# =====================================================================
# Shared setup for (e)-(h): the REAL files of this checkout served at main.
RAW="$BASE/tomacco/aura-distill"
PAYLOAD_FILES="VERSION distill.md distill-process.md distill-monitor.md install.sh install.ps1 INSTALL.md rules/distill.md agents/scribe.md agents/scout.md bin/distill-update.sh channels/manifest.json"
SYN="$HERE/fixtures/synthetic-major"

copy_checkout() { # <dest dir>
  local f
  for f in $PAYLOAD_FILES; do mkdir -p "$1/$(dirname "$f")"; cp "$REPO_ROOT/$f" "$1/$f"; done
}
# main = this checkout as the bridge release 1.2.0, with the synthetic software major
# announced in its manifest; software-2.x = the synthetic software payload; the beta
# manifest on beta/1.2 starts unpublished.
serve_bridge() {
  local r="$SERVE/tomacco/aura-distill"
  rm -rf "$SERVE/tomacco"
  mkdir -p "$r/main" "$r/beta/1.2/channels"
  copy_checkout "$r/main"
  printf '1.2.0\n' > "$r/main/VERSION"
  cp "$SYN/channels/manifest.json" "$r/main/channels/manifest.json"
  cp -R "$HERE/fixtures/endpoints/channel-strategy/software-2.x" "$r/"
  cp "$REPO_ROOT/channels/manifest.json" "$r/beta/1.2/channels/manifest.json"
  mkdir -p "$SERVE/tomacco/claude-distill"
  cp -R "$r/main" "$SERVE/tomacco/claude-distill/"
  cp -R "$r/software-2.x" "$SERVE/tomacco/claude-distill/"
}
make_tag() { # <tag> <line appended to distill-process.md>
  local d="$SERVE/tomacco/aura-distill/$1"
  rm -rf "$d"; mkdir -p "$d"
  copy_checkout "$d"
  printf '%s\n' "${1#v}" > "$d/VERSION"
  printf '\n%s\n' "$2" >> "$d/distill-process.md"
}
set_beta() { # <status> <tag> <version> [software status]
  local sw=${4:-unpublished} v="" req="" guide=""
  if [ "$sw" != unpublished ]; then
    v=2.0.0; req="a local background service started at login, a one-time migration of the knowledge store, and a local network port on 127.0.0.1"
    guide="https://tomacco.github.io/aura-distill/upgrade/2.0.0.md"
  fi
  cat > "$SERVE/tomacco/aura-distill/beta/1.2/channels/manifest.json" <<EOF
{
  "schema": 2,
  "beta": {
    "status": "$1",
    "tag": "$2",
    "version": "$3"
  },
  "software": {
    "status": "$sw",
    "version": "$v",
    "requirements": "$req",
    "guide": "$guide",
    "auto_update": "never"
  }
}
EOF
}
served_main() { printf '%s' "$SERVE/tomacco/aura-distill/main"; }

# Run the checkout's install.sh against the served tree. Extra args go to install.sh.
install_client() { # <home> [install.sh args...]
  local home=$1; shift
  mkdir -p "$home"
  env -u AURA_DISTILL_HOME -u CODEX_HOME -u DISTILL_CHANNEL -u AURA_DISTILL_REPO -u AURA_DISTILL_CHANNEL_MANIFEST \
    HOME="$home" AURA_DISTILL_HOME="$home/.aura-distill" CODEX_HOME="$home/.codex" \
    AURA_DISTILL_RAW_ROOT="$RAW" \
    bash "$REPO_ROOT/install.sh" "$@" </dev/null >"$home/install.log" 2>&1
}
# Run the INSTALLED updater the way the dispatcher does. Output lands in $home/update.out.
run_update() { # <home> <auto|check|apply>
  local home=$1 store
  store=$(store_of "$1")
  env -u AURA_DISTILL_HOME -u AURA_DISTILL_CHANNEL_MANIFEST HOME="$home" AURA_DISTILL_RAW_ROOT="$RAW" \
    bash "$store/bin/distill-update.sh" "$2" >"$home/update.out" 2>"$home/update.err"
}
first_line() { head -1 "$1/update.out"; }
run_update_to() { # <home> <output file>: same as run_update, separate output (concurrent runs)
  local store; store=$(store_of "$1")
  env -u AURA_DISTILL_HOME -u AURA_DISTILL_CHANNEL_MANIFEST HOME="$1" AURA_DISTILL_RAW_ROOT="$RAW" \
    bash "$store/bin/distill-update.sh" apply >"$2" 2>/dev/null
}
set_autoupdate() { # <home> <true|false>
  local store; store=$(store_of "$1")
  mkdir -p "$store/feedback"
  printf -- '---\ndomain: feedback\nscope: distill system preferences\n---\n\n## Auto-update\n- enabled: %s\n' "$2" > "$store/feedback/preferences.md"
}
seed_knowledge() { # <home>
  local store; store=$(store_of "$1")
  mkdir -p "$store/craft"
  printf '# Distill Knowledge Index\n- [Synthetic](craft/synthetic.md) - fixture\n' > "$store/SPINE.md"
  printf 'SYNTHETIC-KNOWLEDGE\n' > "$store/craft/synthetic.md"
}
# Fingerprint of everything an update or install may touch plus the knowledge itself.
snapshot() { # <home>
  local store; store=$(store_of "$1")
  { cat "$1/.claude/commands/distill.md" "$store/distill-process.md" "$store/distill-monitor.md" \
      "$store/.version" "$store/bin/distill-update.sh" "$store/SPINE.md" "$store/craft/synthetic.md" \
      "$store/feedback/preferences.md" "$1/.claude/rules/distill.md" 2>/dev/null || true; } | cksum
}
tag_line() { grep -c "^$2\$" "$(store_of "$1")/distill-process.md" 2>/dev/null || true; }
# Used inside `check ... bash -c "..."` assertions, so they must reach child shells.
export -f snapshot tag_line store_of
mark_log() { wc -l < "$ACCESS_LOG" | tr -d ' '; }
requests_since() { # <line mark> <path fragment>
  tail -n +"$(( $1 + 1 ))" "$ACCESS_LOG" | grep -c "GET $2" || true
}

# pty driver: runs a command on a real terminal and types <answer> at the prompt.
PTY_DRIVER="$WORK/pty-drive.py"
cat > "$PTY_DRIVER" <<'PYEOF'
import os, pty, sys
answer, argv = sys.argv[1], sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(argv[0], argv)
out, sent = b"", False
while True:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    out += chunk
    if not sent and b"press Enter" in out:
        os.write(fd, answer.encode() + b"\n"); sent = True
_, status = os.waitpid(pid, 0)
sys.stdout.write(out.decode(errors="replace"))
sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1)
PYEOF
HAVE_PTY=0
if [ -n "$PY" ] && "$PY" -c 'import pty' >/dev/null 2>&1; then HAVE_PTY=1; fi

# =====================================================================
section "(e) Real bridge at main, synthetic software major announced in its manifest"
serve_bridge
: > "$ACCESS_LOG"
check "the synthetic announced manifest and guide pass the release check" \
  bash "$HERE/check-major-release.sh" "$SYN/channels/manifest.json" "$SYN/docs/upgrade/2.0.0.md"
for spec in "dispatcher-v0.3.1.sh 0.3.1 legacy" "dispatcher-v1.0.0.sh 1.0.1 legacy" "dispatcher-v1.1.17.sh 1.1.17 shared"; do
  set -- $spec
  c=$(new_client "$2" "$3"); s=$(store_of "$c")
  seed_knowledge "$c"; before_k=$(cat "$s/SPINE.md" "$s/craft/synthetic.md" | cksum)
  r=$(run_dispatcher "fixtures/updaters/$1" "$c")
  check "$1 client at $2 (skipped every release since) adopts the real bridge via its shipped block" \
    bash -c "[ '$r' = updated ] && grep -q 'distill-update.sh. auto' '$c/.claude/commands/distill.md'"
  # The bridge's own step 1 + step 2, executed as written in the installed dispatcher.
  # The shipped block did not resolve the placeholder, so step 1's rule applies:
  # ~/.aura-distill if it exists, else ~/.claude/distill (= this client's store).
  boot=$(grep -F 't=$(mktemp) && curl' "$c/.claude/commands/distill.md" | sed -e 's/^ *//' \
         -e "s|https://raw.githubusercontent.com|$BASE|g" -e "s|{DISTILL_DIR}|$s|g")
  HOME="$c" bash -c "$boot" >/dev/null 2>&1 || true
  check "  bridge step 2 installs the updater script (validated, into the client's own store)" test -f "$s/bin/distill-update.sh"
  set_autoupdate "$c" true
  run_update "$c" auto
  check "  bridge step 3 repairs the files the shipped block left unresolved: $(first_line "$c")" \
    bash -c "grep -q '^REPAIRED 1.2.0 stable' '$c/update.out' && ! grep -qF '{DISTILL_DIR}' '$c/.claude/commands/distill.md' '$s/distill-process.md' '$s/distill-monitor.md'"
  check "  the notice names v2.0.0, the requirements and the guide, and nothing else" \
    bash -c "grep -q '^NOTICE: .*software edition (v2.0.0)' '$c/update.out' && grep -q 'local background service' '$c/update.out' && grep -q 'https://tomacco.github.io/aura-distill/upgrade/2.0.0.md' '$c/update.out' && ! grep -q 'software-2.x' '$c/update.out'"
  run_update "$c" auto
  check "  deferred: the next session shows no notice again, and there is nothing left to repair ($(first_line "$c"))" \
    bash -c "! grep -q '^NOTICE' '$c/update.out' && grep -q '^CURRENT 1.2.0 stable' '$c/update.out'"
  check "  no software payload, no consent record, knowledge unchanged" \
    bash -c "! grep -rq '$MARKER' '$c' && [ ! -e '$s/.major-consent' ] && [ \"\$(cat '$s/SPINE.md' '$s/craft/synthetic.md' | cksum)\" = '$before_k' ]"
done
c=$(new_client 1.1.17 shared); s=$(store_of "$c")
run_dispatcher fixtures/updaters/dispatcher-v1.1.17.sh "$c" >/dev/null
boot=$(grep -F 't=$(mktemp) && curl' "$c/.claude/commands/distill.md" | sed -e 's/^ *//' -e "s|https://raw.githubusercontent.com|$BASE|g" -e "s|{DISTILL_DIR}|$s|g")
HOME="$c" bash -c "$boot" >/dev/null 2>&1 || true
# The same bootstrap run VERBATIM, placeholder left in (a model that skips step 1's
# substitution): it must refuse and create nothing, neither a literal "{DISTILL_DIR}"
# directory in the working directory nor anything in the store.
verb=$(grep -F 't=$(mktemp) && curl' "$REPO_ROOT/distill.md" | sed -e 's/^ *//' -e "s|https://raw.githubusercontent.com|$BASE|g")
vcwd=$(mktemp -d "$WORK/clients/verbatim.XXXXXX"); vbefore=$(find "$c" -type f | LC_ALL=C sort | cksum)
vreq=$(requests_to /bin/distill-update.sh)
verr=$( cd "$vcwd" && HOME="$c" bash -c "$verb" 2>&1 >/dev/null ) || true
check "bootstrap template run verbatim (placeholder unsubstituted) refuses and says why" \
  bash -c "printf '%s' \"\$1\" | grep -q 'store path is still a placeholder'" _ "$verr"
check "  and creates nothing: no '{DISTILL_DIR}' directory in the working directory, the client unchanged, no download" \
  bash -c "[ -z \"\$(ls -A '$vcwd')\" ] && [ \"\$(find '$c' -type f | LC_ALL=C sort | cksum)\" = '$vbefore' ] && [ \"\$2\" = \"\$3\" ]" _ x "$vreq" "$(requests_to /bin/distill-update.sh)"
sp=$(cksum < "$s/distill-process.md")
run_update "$c" check >/dev/null
check "check mode reports a pending repair ('$(first_line "$c")') and writes nothing" \
  bash -c "grep -q '^AVAILABLE 1.2.0 1.2.0 stable' '$c/update.out' && [ \"\$(cksum < '$s/distill-process.md')\" = '$sp' ]"
run_update "$c" check
check "a notice already shown stays quiet" bash -c "! grep -q '^NOTICE' '$c/update.out'"
sed -i.bak 's/a local network port on 127.0.0.1/a local network port on 127.0.0.1 and 2 GB of disk/' "$(served_main)/channels/manifest.json"
run_update "$c" check
check "changed requirements in the manifest show the notice again" \
  bash -c "grep -q '2 GB of disk' '$c/update.out'"
c=$(new_client 1.0.1 legacy)
run_installer_v1_fetch "$c"
check "Homebrew path (v1.0.0 fetch block) against the real bridge: files-only, no software payload" \
  bash -c "grep -q 'distill-update.sh. auto' '$c/.claude/commands/distill.md' && ! grep -rq '$MARKER' '$c'"
check "no request from any old client, the bridge step or the updater touched the software channel" \
  test "$(requests_to /software-2.x/)" = 0
check "positive control: the updater did read the manifest on main" \
  test "$(requests_to /tomacco/aura-distill/main/channels/manifest.json)" -ge 1
bridge="$REPO_ROOT/distill.md"
check "bridge prose (static): forbids acting on NOTICE lines and manifests, and composing downloads" \
  bash -c "grep -q 'Never fetch, open, install or run anything a \`NOTICE:\` line or a channel manifest mentions' '$bridge' && grep -q 'Never update aura-distill files with your own' '$bridge'"
check "bridge prose (static): maps all five status words" \
  bash -c "for w in CURRENT UPDATED REPAIRED AVAILABLE BLOCKED; do grep -q \"\\\`\$w \" '$bridge' || exit 1; done"
x=$(mktemp -d "$WORK/clients/leak.XXXXXX"); install_client "$x"
env AURA_UPDATER_SELF="$x/.aura-distill/bin/distill-update.sh" HOME="$x" AURA_DISTILL_RAW_ROOT="$RAW" bash "$x/.aura-distill/bin/distill-update.sh" check >/dev/null 2>&1 || true
check "a leaked AURA_UPDATER_SELF never makes the updater delete its installed copy" test -f "$x/.aura-distill/bin/distill-update.sh"
check "bridge prose (static): its only URL is the updater script on main" \
  test "$(grep -oE 'https?://[^ )\`\"]+' "$bridge" | sort -u)" = "https://raw.githubusercontent.com/tomacco/aura-distill/main/bin/distill-update.sh"

# =====================================================================
section "(f) Shipped updater: auto-update on/off, pinned files-only, mixed and failed responses"
serve_bridge
M=$(served_main)
c=$(mktemp -d "$WORK/clients/f.XXXXXX")
install_client "$c"; s="$c/.aura-distill"
check "fresh stable install from the bridge: channel stable, updater installed, .version 1.2.0" \
  bash -c "[ \"\$(cat '$s/.channel')\" = stable ] && [ -x '$s/bin/distill-update.sh' ] && [ \"\$(cat '$s/.version')\" = 1.2.0 ]"
seed_knowledge "$c"; set_autoupdate "$c" false
run_update "$c" auto >/dev/null   # consume the one-time notice
printf '1.2.1\n' > "$M/VERSION"; printf '\nPATCH-1.2.1\n' >> "$M/distill-process.md"
snap=$(snapshot "$c")
run_update "$c" auto
check "auto-update OFF: reports '$(first_line "$c")' and changes nothing" \
  bash -c "[ \"\$(head -1 '$c/update.out')\" = 'AVAILABLE 1.2.0 1.2.1 stable' ] && [ \"\$(snapshot '$c')\" = '$snap' ]"
set_autoupdate "$c" true
run_update "$c" auto
check "auto-update ON: '$(first_line "$c")', new files in place, .version 1.2.1" \
  bash -c "[ \"\$(head -1 '$c/update.out')\" = 'UPDATED 1.2.0 1.2.1 stable' ] && [ \"\$(tag_line '$c' PATCH-1.2.1)\" = 1 ] && [ \"\$(cat '$s/.version')\" = 1.2.1 ]"
check "  placeholders resolved to this store in the updated dispatcher and process" \
  bash -c "! grep -q '{DISTILL_DIR}' '$c/.claude/commands/distill.md' '$s/distill-process.md' && grep -q '$s/bin/distill-update.sh' '$c/.claude/commands/distill.md'"
check "  knowledge untouched" bash -c "grep -q SYNTHETIC-KNOWLEDGE '$s/craft/synthetic.md' && grep -q Synthetic '$s/SPINE.md'"
check "pinned files-only (stable channel, auto-update on, software edition announced): no software fetch ever" \
  bash -c "! grep -rq '$MARKER' '$c' && [ \"\$(grep -c 'GET .*/software-2.x/' '$ACCESS_LOG')\" = 0 ]"

fail_case() { # <description> ; the served tree was just mutated; nothing may change
  local snap m
  snap=$(snapshot "$c"); m=$(mark_log)
  run_update "$c" auto
  check "$1: '$(first_line "$c")', every installed file unchanged" \
    bash -c "grep -q '^BLOCKED stable' '$c/update.out' && [ \"\$(snapshot '$c')\" = '$snap' ]"
  LAST_MARK=$m
}
printf '2.0.0\n' > "$M/VERSION"
fail_case "mixed: main/VERSION says 2.0.0 over files-only files"
check "  no payload file was even requested" test "$(requests_since "$LAST_MARK" /tomacco/aura-distill/main/distill)" = 0
printf '1.2.2\n' > "$M/VERSION"; cp "$M/distill-monitor.md" "$WORK/monitor.bak"; printf '\n%s\n' "$MARKER" >> "$M/distill-monitor.md"
fail_case "mixed: VERSION 1.2.2 but distill-monitor.md is a software payload (distill.md before it was valid)"
cp "$WORK/monitor.bak" "$M/distill-monitor.md"; mv "$M/distill-process.md" "$WORK/process.bak"
fail_case "failed: distill-process.md returns 404"
printf '<!DOCTYPE html><html>rate limited</html>\n' > "$M/distill-process.md"
fail_case "failed: distill-process.md returns an HTML error page"
: > "$M/distill-process.md"
fail_case "failed: distill-process.md is empty"
mv "$WORK/process.bak" "$M/distill-process.md"; head -c 20 "$M/bin/distill-update.sh" > "$WORK/upd"; cp "$M/bin/distill-update.sh" "$WORK/upd.bak"; cp "$WORK/upd" "$M/bin/distill-update.sh"
fail_case "failed: the updater script itself is truncated"
cp "$WORK/upd.bak" "$M/bin/distill-update.sh"; mv "$M/VERSION" "$WORK/version.bak"
fail_case "failed: VERSION unavailable (offline)"
printf '1.2.3-beta.1\n' > "$M/VERSION"
fail_case "mixed: the stable endpoint reports a prerelease"
printf '1.2.2\n' > "$M/VERSION"
pids=""; for i in 1 2 3; do run_update_to "$c" "$WORK/conc.$i" & pids="$pids $!"; done; for p in $pids; do wait "$p" || true; done
check "three concurrent sessions applying one update: each reports UPDATED or BLOCKED, the result is complete, no temp files left" \
  bash -c "for i in 1 2 3; do head -1 '$WORK/conc.'\$i | grep -Eq '^(UPDATED|BLOCKED|CURRENT) ' || exit 1; done; [ \"\$(cat '$s/.version')\" = 1.2.2 ] && ! ls '$s'/*.aura-new.* '$s/bin/'*.aura-new.* '$c/.claude/commands/'*.aura-new.* >/dev/null 2>&1"
printf '1.2.3\n' > "$M/VERSION"; printf 'not json {{{\n' > "$M/channels/manifest.json"
run_update "$c" auto
check "malformed manifest on main: the files-only update still applies ('$(first_line "$c")'), no notice" \
  bash -c "[ \"\$(head -1 '$c/update.out')\" = 'UPDATED 1.2.2 1.2.3 stable' ] && ! grep -q NOTICE '$c/update.out'"

# =====================================================================
section "(g) Beta channel: opt-in from a pinned tag, beta auto-update, opt-out"
serve_bridge
M=$(served_main)
make_tag v1.2.0-beta.1 BETA-ONE
make_tag v1.2.0-beta.2 BETA-TWO
c=$(mktemp -d "$WORK/clients/g.XXXXXX")
set +e; install_client "$c" --channel beta; rc=$?; set -e
check "no beta published yet: install.sh --channel beta exits $rc and writes nothing" \
  bash -c "[ $rc -ne 0 ] && [ ! -e '$c/.aura-distill' ] && [ ! -e '$c/.claude/commands/distill.md' ]"
set_beta prerelease v1.2.0-beta.1 1.2.0-beta.1
m=$(mark_log)
install_client "$c" --channel beta; s="$c/.aura-distill"
check "install.sh --channel beta installs the tag the manifest names: .channel beta, .version 1.2.0-beta.1" \
  bash -c "[ \"\$(cat '$s/.channel')\" = beta ] && [ \"\$(cat '$s/.version')\" = 1.2.0-beta.1 ] && [ \"\$(tag_line '$c' BETA-ONE)\" = 1 ]"
check "  every payload file came from the tag, none from main" \
  test "$(requests_since "$m" /tomacco/aura-distill/v1.2.0-beta.1/distill)" -ge 3 -a "$(requests_since "$m" /tomacco/aura-distill/main/)" = 0
seed_knowledge "$c"; set_autoupdate "$c" true
printf '1.2.9\n' > "$M/VERSION"
m=$(mark_log)
run_update "$c" auto
check "beta + auto-update ON while main moves to 1.2.9: '$(first_line "$c")' (no downgrade to main)" \
  bash -c "grep -q '^CURRENT 1.2.0-beta.1 beta' '$c/update.out'"
check "  the beta updater never requested anything from main" test "$(requests_since "$m" /tomacco/aura-distill/main/)" = 0
set_beta prerelease v1.2.0-beta.2 1.2.0-beta.2
run_update "$c" auto
check "the manifest moves to beta.2: '$(first_line "$c")', files from the new tag" \
  bash -c "[ \"\$(head -1 '$c/update.out')\" = 'UPDATED 1.2.0-beta.1 1.2.0-beta.2 beta' ] && [ \"\$(tag_line '$c' BETA-TWO)\" = 1 ] && [ \"\$(tag_line '$c' BETA-ONE)\" = 0 ]"
printf '\357\273\277beta\r\n' > "$s/.channel"; printf '\357\273\2771.2.0-beta.2\r\n' > "$s/.version"
run_update "$c" auto
check "store metadata with a UTF-8 BOM and CRLF (as Windows PowerShell 5.1 writes it) still reads as beta: '$(first_line "$c")'" \
  bash -c "grep -q '^CURRENT 1.2.0-beta.2 beta' '$c/update.out'"
printf 'beta\n' > "$s/.channel"; printf '1.2.0-beta.2\n' > "$s/.version"
set_autoupdate "$c" false
set_beta prerelease v1.2.0-beta.1 1.2.0-beta.1
run_update "$c" auto
check "beta + auto-update OFF: reports '$(first_line "$c")' only" bash -c "grep -q '^AVAILABLE 1.2.0-beta.2 1.2.0-beta.1 beta' '$c/update.out' && [ \"\$(tag_line '$c' BETA-TWO)\" = 1 ]"
set_autoupdate "$c" true
beta_block() { # <description>
  local snap m
  snap=$(snapshot "$c"); m=$(mark_log)
  run_update "$c" auto
  check "$1: '$(first_line "$c")', nothing changed" \
    bash -c "grep -q '^BLOCKED beta' '$c/update.out' && [ \"\$(snapshot '$c')\" = '$snap' ]"
  LAST_MARK=$m
}
set_beta prerelease v2.0.0-beta.1 2.0.0-beta.1
beta_block "the beta manifest names a new major (v2.0.0-beta.1)"
check "  nothing was requested from that tag" test "$(requests_since "$LAST_MARK" /v2.0.0-beta.1/)" = 0
c4=$(mktemp -d "$WORK/clients/g4.XXXXXX"); m=$(mark_log)
set +e; install_client "$c4" --channel beta; rc=$?; set -e
check "install.sh --channel beta refuses a v2 beta tag before fetching from it (exit $rc, nothing written)" \
  bash -c "[ $rc -ne 0 ] && [ ! -e '$c4/.aura-distill' ] && [ \"\$(tail -n +$((m+1)) '$ACCESS_LOG' | grep -c 'GET .*/v2.0.0-beta.1/')\" = 0 ]"
set_beta prerelease v1.2.0-beta.3 1.2.0-beta.2
beta_block "tag and version disagree in the manifest"
make_tag v1.2.0-beta.3 BETA-THREE; printf '1.2.0-beta.4\n' > "$SERVE/tomacco/aura-distill/v1.2.0-beta.3/VERSION"
set_beta prerelease v1.2.0-beta.3 1.2.0-beta.3
beta_block "the tag serves a different VERSION than the manifest says"
set_beta prerelease 'v1.2.0-beta.1/../../main' 1.2.0-beta.1
beta_block "a tag with a path in it"
set_beta closed "" ""
beta_block "the beta channel is closed"
rm -f "$SERVE/tomacco/aura-distill/beta/1.2/channels/manifest.json"
beta_block "the beta manifest is unavailable"
set_beta prerelease v1.2.0-beta.2 1.2.0-beta.2 prerelease
run_update "$c" auto
check "beta users see a software PRERELEASE notice (they opted into prereleases)" bash -c "grep -q '^NOTICE: .*v2.0.0' '$c/update.out'"
install_client "$c"
check "re-running the installer without --channel keeps the persisted beta choice" \
  bash -c "[ \"\$(cat '$s/.channel')\" = beta ] && [ \"\$(cat '$s/.version')\" = 1.2.0-beta.2 ]"
m=$(mark_log)
install_client "$c" --channel stable
check "opt-out: install.sh --channel stable installs main (1.2.9) and records stable" \
  bash -c "[ \"\$(cat '$s/.channel')\" = stable ] && [ \"\$(cat '$s/.version')\" = 1.2.9 ] && [ \"\$(tag_line '$c' BETA-TWO)\" = 0 ] && grep -q SYNTHETIC-KNOWLEDGE '$s/craft/synthetic.md'"
check "  the opt-out install requested nothing from the beta channel" \
  test "$(requests_since "$m" /tomacco/aura-distill/beta/)" = 0 -a "$(requests_since "$m" /tomacco/aura-distill/v1.)" = 0
printf '1.2.10\n' > "$M/VERSION"
m=$(mark_log)
run_update "$c" auto
check "after opt-out the updater follows stable ('$(first_line "$c")') and never asks the beta channel" \
  bash -c "grep -q '^UPDATED 1.2.9 1.2.10 stable' '$c/update.out'" 
check "  zero beta requests" test "$(requests_since "$m" /tomacco/aura-distill/beta/)" = 0 -a "$(requests_since "$m" /tomacco/aura-distill/v1.)" = 0
check "  the stable manifest lists the software edition as stable, so the stable client may see it; no software fetch" \
  test "$(requests_to /software-2.x/)" = 0
c2=$(mktemp -d "$WORK/clients/g2.XXXXXX")
env -u AURA_DISTILL_HOME -u CODEX_HOME -u AURA_DISTILL_REPO HOME="$c2" AURA_DISTILL_HOME="$c2/.aura-distill" CODEX_HOME="$c2/.codex" \
  AURA_DISTILL_RAW_ROOT="$RAW" DISTILL_CHANNEL=beta bash "$REPO_ROOT/install.sh" </dev/null >/dev/null 2>&1 || true
check "DISTILL_CHANNEL=beta works like --channel beta (parity with install.ps1)" \
  bash -c "[ \"\$(cat '$c2/.aura-distill/.channel' 2>/dev/null)\" = beta ]"
c3=$(mktemp -d "$WORK/clients/g3.XXXXXX")
m=$(mark_log)
install_client "$c3"; seed_knowledge "$c3"; set_autoupdate "$c3" true; run_update "$c3" auto
check "a stable install next to a live beta channel never requests a beta URL" \
  test "$(requests_since "$m" /tomacco/aura-distill/beta/)" = 0 -a "$(requests_since "$m" /tomacco/aura-distill/v1.)" = 0

# =====================================================================
section "(h) Installers: fresh install, non-interactive refusal, typed consent, failed downloads"
serve_bridge
M=$(served_main)
c=$(mktemp -d "$WORK/clients/h.XXXXXX")
install_client "$c"
check "fresh install: .command-path points at the installed dispatcher" \
  bash -c "[ \"\$(cat '$c/.aura-distill/.command-path')\" = '$c/.claude/commands/distill.md' ]"
amp=$(mktemp -d "$WORK/clients/h-amp.XXXXXX")
env -u AURA_DISTILL_HOME -u CODEX_HOME -u AURA_DISTILL_REPO HOME="$amp" AURA_DISTILL_HOME="$amp/my store&co|x/.aura-distill" CODEX_HOME="$amp/.codex" \
  AURA_DISTILL_RAW_ROOT="$RAW" bash "$REPO_ROOT/install.sh" </dev/null >/dev/null 2>&1 || true
check "a store path containing '&' and '|' is written literally into the installed files" \
  bash -c "grep -qF '$amp/my store&co|x/.aura-distill/bin/distill-update.sh' '$amp/.claude/commands/distill.md' && ! grep -qF '{DISTILL_DIR}' '$amp/.claude/commands/distill.md' '$amp/my store&co|x/.aura-distill/distill-process.md' '$amp/.claude/rules/distill.md'"
printf '2.0.0\n' > "$M/VERSION"
c=$(mktemp -d "$WORK/clients/h1.XXXXXX")
set +e; install_client "$c"; rc=$?; set -e
check "fresh install, payload major 2.0.0, no terminal: exit $rc, nothing written" \
  bash -c "[ $rc = 2 ] && [ ! -e '$c/.aura-distill' ] && [ ! -e '$c/.claude' ] && grep -q 'No interactive terminal' '$c/install.log'"
printf '1.2.0\n' > "$M/VERSION"
c=$(mktemp -d "$WORK/clients/h2.XXXXXX"); install_client "$c"; seed_knowledge "$c"; snap=$(snapshot "$c")
printf '2.0.0\n' > "$M/VERSION"
set +e
printf 'adopt 2.0.0\n' | env -u AURA_DISTILL_HOME -u CODEX_HOME -u AURA_DISTILL_REPO HOME="$c" AURA_DISTILL_HOME="$c/.aura-distill" CODEX_HOME="$c/.codex" \
  AURA_DISTILL_RAW_ROOT="$RAW" bash "$REPO_ROOT/install.sh" >"$c/install.log" 2>&1; rc=$?
set -e
check "existing install, piped 'adopt 2.0.0' with redirected output: exit $rc, every file unchanged" \
  bash -c "[ $rc = 2 ] && [ \"\$(snapshot '$c')\" = '$snap' ]"
if [ "$HAVE_PTY" = 1 ]; then
  pty_install() { # <home> <answer>
    env -u AURA_DISTILL_HOME -u CODEX_HOME -u AURA_DISTILL_REPO HOME="$1" AURA_DISTILL_HOME="$1/.aura-distill" CODEX_HOME="$1/.codex" \
      AURA_DISTILL_RAW_ROOT="$RAW" "$PY" "$PTY_DRIVER" "$2" bash "$REPO_ROOT/install.sh" >"$1/install.log" 2>&1
  }
  set +e; pty_install "$c" ""; rc=$?; set -e
  check "terminal + Enter (deferred): exit $rc, every file unchanged" bash -c "[ $rc = 2 ] && [ \"\$(snapshot '$c')\" = '$snap' ]"
  set +e; pty_install "$c" "yes"; rc=$?; set -e
  check "terminal + 'yes': exit $rc, every file unchanged" bash -c "[ $rc = 2 ] && [ \"\$(snapshot '$c')\" = '$snap' ]"
  set +e; pty_install "$c" "adopt 2.0.0"; rc=$?; set -e
  check "terminal + typed 'adopt 2.0.0': exit $rc, files-only 2.0.0 installed, knowledge kept" \
    bash -c "[ $rc = 0 ] && [ \"\$(cat '$c/.aura-distill/.version')\" = 2.0.0 ] && grep -q SYNTHETIC-KNOWLEDGE '$c/.aura-distill/craft/synthetic.md'"
else
  printf '  SKIP  installer typed-consent paths (needs Python with the pty module)\n'
fi
printf '1.2.2\n' > "$M/VERSION"
c=$(mktemp -d "$WORK/clients/h3.XXXXXX"); install_client "$c"; seed_knowledge "$c"; snap=$(snapshot "$c")
printf '1.2.3\n' > "$M/VERSION"; mv "$M/distill-monitor.md" "$WORK/mon.bak"
set +e; install_client "$c"; rc=$?; set -e
check "re-install with distill-monitor.md 404: exit $rc, every file unchanged" \
  bash -c "[ $rc -ne 0 ] && [ \"\$(snapshot '$c')\" = '$snap' ]"
cp "$WORK/mon.bak" "$M/distill-monitor.md"; printf '\n%s\n' "$MARKER" >> "$M/distill-process.md"
set +e; install_client "$c"; rc=$?; set -e
check "re-install where main serves a software payload under a 1.x VERSION: exit $rc, every file unchanged" \
  bash -c "[ $rc -ne 0 ] && [ \"\$(snapshot '$c')\" = '$snap' ] && grep -q 'software-edition payload' '$c/install.log'"

# =====================================================================
section "(i) CI endpoint guard and major-release check"
GUARD="$HERE/check-endpoints.sh"
check "this checkout passes the guard" bash "$GUARD" "$REPO_ROOT"
guard_tree() { # -> fresh copy of the frozen files + docs guide dir
  local t; t=$(mktemp -d "$WORK/guard.XXXXXX")
  copy_checkout "$t"; printf '%s' "$t"
}
guard_rejects() { # <description> <surface> <expected reason substring> <mutation command run in the copy>
  local T; T=$(guard_tree)
  (cd "$T" && eval "$4")
  bash "$GUARD" --surface "$2" "$T" > "$T.out" 2>&1 && rc=0 || rc=$?
  check "guard rejects: $1" bash -c "[ $rc -ne 0 ] && grep -qF -- '$3' '$T.out'"
}
guard_rejects "a software-branch raw URL in rules/distill.md" beta "rules/distill.md references software-2.x" \
  "printf 'see https://raw.githubusercontent.com/tomacco/aura-distill/software-2.x/distill.md\n' >> rules/distill.md"
guard_rejects "the software base built from RAW_ROOT in install.sh" beta "install.sh references software-2.x" \
  "printf 'X=\"\$RAW_ROOT/software-2.x/install.sh\"\n' >> install.sh"
guard_rejects "a v2 tag URL in install.ps1" beta "install.ps1 references v2.0.0" \
  "printf '# https://raw.githubusercontent.com/tomacco/aura-distill/v2.0.0/install.ps1\n' >> install.ps1"
guard_rejects "a beta URL in distill-monitor.md (only installers/updater/INSTALL.md may)" beta "distill-monitor.md references the beta channel" \
  "printf 'https://raw.githubusercontent.com/tomacco/aura-distill/beta/1.2/x\n' >> distill-monitor.md"
guard_rejects "the pre-rename path to a software branch in distill.md" beta "distill.md references software-2.x" \
  "printf 'https://raw.githubusercontent.com/tomacco/claude-distill/software-2.x/VERSION\n' >> distill.md"
guard_rejects "the software payload marker in distill-process.md" beta "distill-process.md contains the software-edition payload marker" \
  "printf '%s\n' '$MARKER' >> distill-process.md"
guard_rejects "software.base in the manifest" beta "software.base must not exist" \
  "sed 's/\"auto_update\": \"never\"/\"auto_update\": \"never\",\\
    \"base\": \"https:\/\/raw.githubusercontent.com\/tomacco\/aura-distill\/main\"/' channels/manifest.json > m && mv m channels/manifest.json"
guard_rejects "main/VERSION carrying 2.0.0" beta "is not on the files-only line" "printf '2.0.0\n' > VERSION"
guard_rejects "a prerelease VERSION on the stable surface" stable "is a prerelease" "printf '1.2.0-beta.1\n' > VERSION"
T=$(guard_tree); printf '1.2.0-beta.1\n' > "$T/VERSION"
check "guard accepts a prerelease VERSION on the beta surface" bash "$GUARD" --surface beta "$T"
guard_rejects "a non-canonical (single-line) manifest" beta "not in canonical form" \
  "tr -d '\n' < channels/manifest.json > m && printf '\n' >> m && mv m channels/manifest.json"
guard_rejects "a deleted legacy endpoint (agents/scout.md)" beta "agents/scout.md is missing" "rm agents/scout.md"
guard_rejects "an announced software entry whose guide misses a section" beta "fails check-major-release.sh" \
  "cp '$SYN/channels/manifest.json' channels/manifest.json && mkdir -p docs/upgrade && grep -v '^## Rollback' '$SYN/docs/upgrade/2.0.0.md' > docs/upgrade/2.0.0.md"
T=$(guard_tree); cp "$SYN/channels/manifest.json" "$T/channels/manifest.json"; mkdir -p "$T/docs/upgrade"; cp "$SYN/docs/upgrade/2.0.0.md" "$T/docs/upgrade/"
check "guard accepts the complete synthetic announcement (manifest + guide on Pages)" bash "$GUARD" "$T"
T=$(mktemp -d "$WORK/mr.XXXXXX"); sed 's/"requirements": "[^"]*"/"requirements": ""/' "$SYN/channels/manifest.json" > "$T/m.json"
check "major-release check rejects empty requirements" bash -c "! bash '$HERE/check-major-release.sh' '$T/m.json' '$SYN/docs/upgrade/2.0.0.md' >/dev/null"
sed 's/"version": "2.0.0"/"version": "1.9.0"/' "$SYN/channels/manifest.json" > "$T/m.json"
check "major-release check rejects an entry that is not a new major" bash -c "! bash '$HERE/check-major-release.sh' '$T/m.json' '$SYN/docs/upgrade/2.0.0.md' >/dev/null"

# =====================================================================
section "(j) Store metadata: non-ASCII paths, byte-order marks, CRLF, several profiles"
serve_bridge
M=$(served_main)
c=$(mktemp -d "$WORK/clients/j.XXXXXX")
mkdir -p "$c/.claude" "$c/.claude-mûller"
install_client "$c" --profile mûller
s="$c/.aura-distill"
check "a --profile install whose path contains 'û' records it intact" \
  bash -c "grep -qxF '$c/.claude-mûller/commands/distill.md' '$s/.command-path'"
seed_knowledge "$c"; set_autoupdate "$c" true
printf '\357\273\277%s\r\n' "$c/.claude-mûller/commands/distill.md" > "$s/.command-path"
printf '1.2.1\n' > "$M/VERSION"; printf '\nPATCH-J1\n' >> "$M/distill.md"
run_update "$c" auto
check "BOM + CRLF .command-path with a non-ASCII path: the 'û' profile's dispatcher is updated ('$(first_line "$c")')" \
  bash -c "grep -q '^UPDATED 1.2.0 1.2.1 stable' '$c/update.out' && grep -q PATCH-J1 '$c/.claude-mûller/commands/distill.md'"
check "  and nothing is written into the default profile" test ! -e "$c/.claude/commands/distill.md"
# CRLF preferences (a Windows editor): the opt-in must still count.
printf -- '---\r\ndomain: feedback\r\n---\r\n\r\n## Auto-update\r\n- enabled: true\r\n' > "$s/feedback/preferences.md"
printf '1.2.2\n' > "$M/VERSION"
run_update "$c" auto
check "a CRLF preferences.md with 'enabled: true' still auto-applies ('$(first_line "$c")')" \
  bash -c "grep -q '^UPDATED 1.2.1 1.2.2 stable' '$c/update.out'"
# Two profiles on one store: both dispatchers are listed and both are updated.
install_client "$c" --profile default
check "a second profile's install appends its dispatcher to .command-path (2 entries, no duplicates)" \
  bash -c "[ \"\$(grep -c . '$s/.command-path')\" = 2 ] && grep -qxF '$c/.claude/commands/distill.md' '$s/.command-path'"
install_client "$c" --profile default
check "  re-installing the same profile adds nothing" bash -c "[ \"\$(grep -c . '$s/.command-path')\" = 2 ]"
set_autoupdate "$c" true
printf '1.2.3\n' > "$M/VERSION"; printf '\nPATCH-J3\n' >> "$M/distill.md"
run_update "$c" auto
check "one update refreshes every listed profile's dispatcher ('$(first_line "$c")')" \
  bash -c "grep -q '^UPDATED 1.2.2 1.2.3 stable' '$c/update.out' && grep -q PATCH-J3 '$c/.claude/commands/distill.md' && grep -q PATCH-J3 '$c/.claude-mûller/commands/distill.md'"
# Optional store checker (#78): absent from the release -> skipped, an installed copy kept.
printf '#!/usr/bin/env bash\n# aura-distill-check-store invariants v0\necho OLD-CHECKER\n' > "$s/bin/distill-check-store.sh"
printf '1.2.31\n' > "$M/VERSION"
run_update "$c" auto
check "optional checker absent from the release: update succeeds ('$(first_line "$c")'), installed copy untouched" \
  bash -c "grep -q '^UPDATED 1.2.3 1.2.31 stable' '$c/update.out' && grep -q OLD-CHECKER '$s/bin/distill-check-store.sh'"
printf '#!/usr/bin/env bash\n# something else\necho BAD-CHECKER\n' > "$M/bin/distill-check-store.sh"
printf '1.2.32\n' > "$M/VERSION"
run_update "$c" auto
check "optional checker with a wrong header: skipped ('$(first_line "$c")'), installed copy untouched" \
  bash -c "grep -q '^UPDATED 1.2.31 1.2.32 stable' '$c/update.out' && grep -q OLD-CHECKER '$s/bin/distill-check-store.sh'"
printf '#!/usr/bin/env bash\n# aura-distill-check-store invariants v1\necho NEW-CHECKER\n' > "$M/bin/distill-check-store.sh"
printf '1.2.33\n' > "$M/VERSION"
run_update "$c" auto
check "optional checker present with the expected header: installed with the update ('$(first_line "$c")')" \
  bash -c "grep -q '^UPDATED 1.2.32 1.2.33 stable' '$c/update.out' && grep -q NEW-CHECKER '$s/bin/distill-check-store.sh' && [ -x '$s/bin/distill-check-store.sh' ]"
rm -f "$M/bin/distill-check-store.sh"
# rules/distill.md: the user's filled preferences survive an update byte for byte.
R="$c/.claude-mûller/rules/distill.md"
printf '\n**Always answer in bullet points.** (user rule, synthetic)\n- keep: é û » ¿ bytes\n' >> "$R"
sed -n '/^## Always-On User Preferences/,$p' "$R" > "$WORK/prefs.before"
printf '\nRULES-J-NEW-BODY\n' > "$WORK/rules-extra"
sed '/^## Always-On User Preferences/,$d' "$M/rules/distill.md" > "$WORK/rules.body"
{ cat "$WORK/rules.body" "$WORK/rules-extra"; sed -n '/^## Always-On User Preferences/,$p' "$M/rules/distill.md"; } > "$M/rules/distill.md.new" && mv "$M/rules/distill.md.new" "$M/rules/distill.md"
printf '1.2.34\n' > "$M/VERSION"
run_update "$c" auto
check "rules/distill.md is updated with the release ('$(first_line "$c")') and the user's preferences survive byte for byte" \
  bash -c "grep -q '^UPDATED 1.2.33 1.2.34 stable' '$c/update.out' && grep -q RULES-J-NEW-BODY '$R' && sed -n '/^## Always-On User Preferences/,\$p' '$R' | cmp -s - '$WORK/prefs.before' && ! grep -qF '{DISTILL_DIR}' '$R'"
check "  the sibling profile's rules file is updated too" grep -q RULES-J-NEW-BODY "$c/.claude/rules/distill.md"
cp "$R" "$WORK/rules.kept"
sed '/^## Always-On User Preferences/,$d' "$M/rules/distill.md" > "$M/rules/distill.md.new" && mv "$M/rules/distill.md.new" "$M/rules/distill.md"
printf '\nRULES-WITHOUT-PREFS-SECTION\n' >> "$M/rules/distill.md"
printf '1.2.345\n' > "$M/VERSION"
run_update "$c" auto
check "a released rules file without the preferences heading leaves every rules file untouched; the rest updates ('$(first_line "$c")')" \
  bash -c "grep -q '^UPDATED 1.2.34 1.2.345 stable' '$c/update.out' && cmp -s '$R' '$WORK/rules.kept' && ! grep -q RULES-WITHOUT '$c/.claude/rules/distill.md'"
cp "$REPO_ROOT/rules/distill.md" "$M/rules/distill.md"
# Two names for one dispatcher (a symlinked profile dir; a non-canonical spelling, as
# Git Bash's /c/... next to C:/...): one target, no "partially updated" loop.
ln -s ".claude-mûller" "$c/.claude-alias"
printf '%s\n%s\n' "$c/.claude-alias/commands/distill.md" "$c/./.claude-mûller/commands/distill.md" >> "$s/.command-path"
printf '1.2.36\n' > "$M/VERSION"
run_update "$c" auto
check "a symlinked alias and a non-canonical spelling of one dispatcher are one target ('$(first_line "$c")'), no temp files left" \
  bash -c "grep -q '^UPDATED 1.2.345 1.2.36 stable' '$c/update.out' && ! ls '$c/.claude-mûller/commands/'*.aura-new.* >/dev/null 2>&1"
run_update "$c" auto
check "  and the next run is CURRENT, not a repeated partial update" bash -c "grep -q '^CURRENT 1.2.36 stable' '$c/update.out'"

# No listed dispatcher exists on this machine: the default profile's is used with a
# notice; with no default either, nothing changes (and .version is not bumped).
k=$(mktemp -d "$WORK/clients/k.XXXXXX"); install_client "$k"; ks="$k/.aura-distill"; set_autoupdate "$k" true
printf '%s\n' "/nonexistent-elsewhere/.claude/commands/distill.md" > "$ks/.command-path"
printf '1.2.37\n' > "$M/VERSION"; printf '\nPATCH-K\n' >> "$M/distill.md"
run_update "$k" auto
check "no listed dispatcher here: the default profile's is updated ('$(first_line "$k")') and a notice names it" \
  bash -c "grep -q '^UPDATED 1.2.36 1.2.37 stable' '$k/update.out' && grep -q PATCH-K '$k/.claude/commands/distill.md' && grep -q '^NOTICE: .*default profile' '$k/update.out'"
rm "$k/.claude/commands/distill.md"
printf '1.2.38\n' > "$M/VERSION"
run_update "$k" check
check "check reports the same BLOCKED that apply would ('$(first_line "$k")'), never AVAILABLE" \
  bash -c "grep -q '^BLOCKED stable no /distill command' '$k/update.out'"
run_update "$k" auto
check "no dispatcher at all on this machine: '$(first_line "$k")', .version not bumped, nothing created" \
  bash -c "grep -q '^BLOCKED stable no /distill command' '$k/update.out' && [ \"\$(cat '$ks/.version')\" = 1.2.37 ] && [ ! -e '$k/.claude/commands/distill.md' ]"
# Two stores on one machine: the default profile uses store A, a work profile store B.
# With B's dispatcher removed, B's updater must not adopt A's default dispatcher.
t2=$(mktemp -d "$WORK/clients/twostores.XXXXXX")
install_client "$t2"
mkdir -p "$t2/.claude-work"
env -u AURA_DISTILL_HOME -u CODEX_HOME -u DISTILL_CHANNEL -u AURA_DISTILL_REPO HOME="$t2" AURA_DISTILL_HOME="$t2/storeB" CODEX_HOME="$t2/.codex" \
  AURA_DISTILL_RAW_ROOT="$RAW" bash "$REPO_ROOT/install.sh" --profile work </dev/null >/dev/null 2>&1
rm "$t2/.claude-work/commands/distill.md"
before_a=$(cat "$t2/.claude/commands/distill.md" "$t2/.claude/rules/distill.md" | cksum)
printf '1.2.39\n' > "$M/VERSION"
env -u AURA_DISTILL_HOME HOME="$t2" AURA_DISTILL_RAW_ROOT="$RAW" bash "$t2/storeB/bin/distill-update.sh" apply > "$t2/b.out" 2>&1 || true
check "two stores: B's updater with B's dispatcher removed reports '$(head -1 "$t2/b.out")' and leaves A's dispatcher and rules untouched" \
  bash -c "grep -q '^BLOCKED stable no /distill command' '$t2/b.out' && [ \"\$(cat '$t2/.claude/commands/distill.md' '$t2/.claude/rules/distill.md' | cksum)\" = '$before_a' ] && grep -qF '$t2/.aura-distill/' '$t2/.claude/commands/distill.md'"
k2=$(mktemp -d "$WORK/clients/k2.XXXXXX"); mkdir -p "$k2/store/bin"; cp "$REPO_ROOT/bin/distill-update.sh" "$k2/store/bin/"
printf '1.2.0\n' > "$k2/store/.version"
env -u AURA_DISTILL_HOME HOME="$k2/home" AURA_DISTILL_RAW_ROOT="$RAW" bash "$k2/store/bin/distill-update.sh" apply > "$k2/out" 2>&1 || true
check "a store with no list and no ~/.claude never creates a profile or rules file" \
  bash -c "grep -q '^BLOCKED' '$k2/out' && [ ! -e '$k2/home/.claude' ]"

# The preferences rule, the same in the updater and in install.sh: the section is kept
# byte for byte unless it equals the shipped template ignoring whitespace.
TEMPLATE_SECTION=$(sed -n '/^## Always-On User Preferences/,$p' "$REPO_ROOT/rules/distill.md")
prefs_case() { # <name> <mode: updater|installer> <section text, or MISSING>
  local h r
  h=$(mktemp -d "$WORK/clients/p.XXXXXX"); install_client "$h"; set_autoupdate "$h" true
  r="$h/.claude/rules/distill.md"
  sed '/^## Always-On User Preferences/,$d' "$r" > "$r.body"
  if [ "$3" = MISSING ]; then printf 'OLD-FILE-WITHOUT-HEADING\n' > "$r"
  else { cat "$r.body"; printf '%s\n' "$3" | sed "s|@STORE@|$h/.aura-distill|g"; } > "$r"; fi
  rm -f "$r.body"
  sed -n '/^## Always-On User Preferences/,$p' "$r" > "$h/prefs.before"
  PREFS_SEQ=$((PREFS_SEQ+1)); printf '1.3.%s\n' "$PREFS_SEQ" > "$M/VERSION"
  if [ "$2" = updater ]; then run_update "$h" auto; else install_client "$h"; fi
  PREFS_HOME=$h
}
PREFS_SEQ=0
for mode in updater installer; do
  prefs_case bullets "$mode" "$(printf '## Always-On User Preferences\n\n- Answer in bullet points.\n- Never use emoji.')"
  check "$mode: bullet-only preferences (no bold line) survive byte for byte" \
    bash -c "sed -n '/^## Always-On User Preferences/,\$p' '$PREFS_HOME/.claude/rules/distill.md' | cmp -s - '$PREFS_HOME/prefs.before'"
  prefs_case prose "$mode" "$(printf '## Always-On User Preferences\n\nKeep answers short; ask before large refactors.')"
  check "$mode: prose preferences survive byte for byte" \
    bash -c "sed -n '/^## Always-On User Preferences/,\$p' '$PREFS_HOME/.claude/rules/distill.md' | cmp -s - '$PREFS_HOME/prefs.before'"
  prefs_case nonascii "$mode" "$(printf '## Always-On User Preferences\n\n- Responde en español, sin «adornos» ¿vale? — ûÿ\n')"
  check "$mode: non-ASCII preferences survive byte for byte" \
    bash -c "sed -n '/^## Always-On User Preferences/,\$p' '$PREFS_HOME/.claude/rules/distill.md' | cmp -s - '$PREFS_HOME/prefs.before'"
  prefs_case template "$mode" "$(printf '%s\n\n\n' "$(printf '%s' "$TEMPLATE_SECTION" | sed "s|{DISTILL_DIR}|@STORE@|g; s/\$/  /")")"
  check "$mode: an untouched template section (whitespace differs) is replaced by the release's" \
    bash -c "! cmp -s <(sed -n '/^## Always-On User Preferences/,\$p' '$PREFS_HOME/.claude/rules/distill.md') '$PREFS_HOME/prefs.before' && ! sed -n '/^## Always-On User Preferences/,\$p' '$PREFS_HOME/.claude/rules/distill.md' | grep -q '  \$'"
  prefs_case missing "$mode" MISSING
  check "$mode: a rules file without the heading is replaced by the release's" \
    bash -c "! grep -q OLD-FILE-WITHOUT-HEADING '$PREFS_HOME/.claude/rules/distill.md' && grep -q '^## Always-On User Preferences' '$PREFS_HOME/.claude/rules/distill.md'"
done

rm "$c/.claude/commands/distill.md"   # the user uninstalls /distill from the default profile
printf '1.2.35\n' > "$M/VERSION"
run_update "$c" auto
check "an uninstalled dispatcher stays uninstalled; the sibling profile still updates ('$(first_line "$c")')" \
  bash -c "grep -q '^UPDATED 1.2.36 1.2.35 stable' '$c/update.out' && [ ! -e '$c/.claude/commands/distill.md' ] && [ \"\$(cat '$s/.version')\" = 1.2.35 ]"
printf '%s\n' "/nonexistent-elsewhere/.claude/commands/distill.md" >> "$s/.command-path"
printf '1.2.4\n' > "$M/VERSION"
run_update "$c" auto
check "a listed path from another machine is skipped, the others still update ('$(first_line "$c")')" \
  bash -c "grep -q '^UPDATED 1.2.35 1.2.4 stable' '$c/update.out' && [ ! -e /nonexistent-elsewhere ]"

# =====================================================================
section "Isolation: nothing escaped the sandbox"
check "AURA_DISTILL_HOME/CODEX_HOME inherited from the environment were never written to" \
  test ! -e "$CANARY"

printf '\nRESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
