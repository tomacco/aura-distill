#!/usr/bin/env bash
# Legacy endpoint guard (docs/adr/0001 "Historical URLs that stay safe forever",
# docs/adr/0002). Fails when a file that some shipped updater or installer fetches
# from a fixed URL could hand an old client something other than the files-only line.
#
# Usage: check-endpoints.sh [--surface stable|beta] [ROOT]
#   --surface stable  the tree is (or is about to become) main: VERSION must be a
#                     plain x.y.z; a prerelease on main would reach every legacy client
#   --surface beta    (default) prerelease VERSION values are allowed
#   ROOT              tree to check (default: this repository)
#
# Checks, all against the files served at the legacy root paths:
#   1. every frozen endpoint file exists (they may never be deleted or moved)
#   2. none contains the software-edition payload marker
#   3. every tomacco/{aura,claude}-distill URL names an allowed ref: main anywhere;
#      beta/1.2 only in the installers, the updater script and INSTALL.md; v1.x tags
#      only in INSTALL.md; anything else (a software branch, a v2+ tag) fails
#   4. VERSION is on the files-only major (1); plain x.y.z on the stable surface
#   5. channels/manifest.json is canonical one-key-per-line JSON, its software entry
#      has no base and no URL except a Pages guide, auto_update is "never", and an
#      announced software entry passes check-major-release.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SURFACE=beta
if [ "${1:-}" = "--surface" ]; then SURFACE=${2:-}; shift 2; fi
case "$SURFACE" in stable|beta) ;; *) echo "usage: check-endpoints.sh [--surface stable|beta] [ROOT]" >&2; exit 64 ;; esac
ROOT=$(cd "${1:-$HERE/../..}" && pwd)

ERRORS=0
err() { ERRORS=$((ERRORS+1)); printf 'ENDPOINT-GUARD: %s\n' "$1"; }

MARKER="AURA_SOFTWARE_""MAJOR_PAYLOAD"
FROZEN="VERSION distill.md distill-process.md distill-monitor.md install.sh install.ps1 INSTALL.md rules/distill.md agents/scribe.md agents/scout.md bin/distill-update.sh channels/manifest.json"
BETA_OK="install.sh install.ps1 bin/distill-update.sh INSTALL.md"
TAG_OK="INSTALL.md"

in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

for f in $FROZEN; do
  p="$ROOT/$f"
  if [ ! -f "$p" ]; then err "$f is missing: legacy endpoint files may never be deleted or moved"; continue; fi
  if grep -q "$MARKER" "$p"; then err "$f contains the software-edition payload marker"; fi
  # Every reference into this repository (and its pre-rename path) with its ref.
  refs=$(grep -oE '(raw\.githubusercontent\.com/tomacco/(aura|claude)-distill|github\.com/tomacco/(aura|claude)-distill/(archive/refs/tags|archive|tree|blob|raw|releases/download))/[A-Za-z0-9._/-]+' "$p" 2>/dev/null \
         | sed -E 's#^(raw\.githubusercontent\.com/tomacco/[a-z-]+|github\.com/tomacco/[a-z-]+/(archive/refs/tags|archive|tree|blob|raw|releases/download))/##' | sort -u)
  # Refs built from the raw-root variable ("$RAW_ROOT/main", "$RawRoot/beta/1.2/...").
  # A ref held in another variable ("$RAW_ROOT/$tag") is validated at run time by the
  # tag pattern in the installers and the updater, so it is not a literal to check.
  vrefs=$(grep -oE '(RAW_ROOT|RawRoot)\}?/[A-Za-z0-9._-]+(/[0-9][A-Za-z0-9._-]*)?' "$p" 2>/dev/null \
          | sed -E 's#^(RAW_ROOT|RawRoot)\}?/##' | sort -u)
  refs="$refs $vrefs"
  for r in $refs; do
    case "$r" in
      main|main/*) ;;
      beta/1.2|beta/1.2/*)
        in_list "$f" "$BETA_OK" || err "$f references the beta channel ($r); only the installers, bin/distill-update.sh and INSTALL.md may" ;;
      v1.[0-9]*)
        if ! in_list "$f" "$TAG_OK" && ! printf '%s' "$r" | grep -Eq '^v1\.0\.0(\.tar\.gz)?$'; then
          err "$f references release tag $r; only INSTALL.md may name a tag"
        fi ;;
      *) err "$f references $r, which is not the files-only line (software channel or unknown ref)" ;;
    esac
  done
done

# 4. VERSION
if [ -f "$ROOT/VERSION" ]; then
  v=$(tr -d '[:space:]' < "$ROOT/VERSION")
  if ! printf '%s' "$v" | grep -Eq '^1\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$'; then
    err "VERSION '$v' is not on the files-only line (1.x.y); main/VERSION never carries another major"
  elif [ "$SURFACE" = stable ] && printf '%s' "$v" | grep -q -- '-'; then
    err "VERSION '$v' is a prerelease; main must carry a plain x.y.z (set it before promoting a beta)"
  fi
fi

# 5. Channel manifest
M="$ROOT/channels/manifest.json"
if [ -f "$M" ]; then
  PY=""
  for c in python3 python; do "$c" -c 'import json' >/dev/null 2>&1 && { PY=$c; break; }; done
  if [ -n "$PY" ]; then
    out=$("$PY" - "$M" "$ROOT" <<'PYEOF'
import json, re, sys
path, root = sys.argv[1], sys.argv[2]
raw = open(path, encoding="utf-8").read()
problems = []
try:
    d = json.loads(raw)
except Exception as e:
    print("channels/manifest.json is not valid JSON: %s" % e); sys.exit(0)
if json.dumps(d, indent=2) + "\n" != raw:
    problems.append("channels/manifest.json is not in canonical form (json.dumps(indent=2) + newline); the shell parsers rely on one key per line")
if set(d) - {"schema", "beta", "software"}:
    problems.append("channels/manifest.json has unknown top-level keys: %s" % sorted(set(d) - {"schema", "beta", "software"}))
for sec in ("beta", "software"):
    for k, val in d.get(sec, {}).items():
        if not isinstance(val, str):
            problems.append("%s.%s must be a string (the shell parsers read strings only)" % (sec, k))
sw = d.get("software", {})
if "base" in sw:
    problems.append("software.base must not exist: the files-only line never learns where the software edition is served")
for k, val in sw.items():
    if k != "guide" and isinstance(val, str) and re.search(r"https?://", val):
        problems.append("software.%s contains a URL; only software.guide may" % k)
guide = sw.get("guide", "")
if guide and not re.fullmatch(r"https://tomacco\.github\.io/aura-distill/[A-Za-z0-9._/-]+", guide):
    problems.append("software.guide must be a page on https://tomacco.github.io/aura-distill/")
if sw.get("auto_update") != "never":
    problems.append('software.auto_update must be "never"')
if sw.get("status") not in ("unpublished", "prerelease", "stable"):
    problems.append("software.status must be unpublished, prerelease or stable")
b = d.get("beta", {})
if b.get("status") not in ("unpublished", "prerelease", "stable", "closed"):
    problems.append("beta.status must be unpublished, prerelease, stable or closed")
if b.get("status") in ("prerelease", "stable"):
    tag, ver = b.get("tag", ""), b.get("version", "")
    if not re.fullmatch(r"v1\.\d+\.\d+(-beta\.\d+)?", tag) or tag[1:] != ver:
        problems.append("beta.tag/beta.version must name one v1.x.y[-beta.n] release (tag = 'v' + version)")
for p in problems:
    print(p)
print("SOFTWARE_STATUS=%s" % sw.get("status", ""))
print("SOFTWARE_GUIDE=%s" % guide)
PYEOF
)
    while IFS= read -r line; do
      case "$line" in
        SOFTWARE_STATUS=*) sw_status=${line#SOFTWARE_STATUS=} ;;
        SOFTWARE_GUIDE=*) sw_guide=${line#SOFTWARE_GUIDE=} ;;
        "") ;;
        *) err "$line" ;;
      esac
    done <<< "$out"
    if [ "${sw_status:-}" = prerelease ] || [ "${sw_status:-}" = stable ]; then
      page=${sw_guide#https://tomacco.github.io/aura-distill/}
      if ! bash "$HERE/check-major-release.sh" "$M" "$ROOT/docs/$page" >/dev/null 2>&1; then
        err "the announced software entry fails check-major-release.sh (guide docs/$page)"
      fi
    fi
  else
    printf 'ENDPOINT-GUARD: SKIP manifest schema checks (no python found)\n'
  fi
fi

if [ "$ERRORS" -gt 0 ]; then
  printf 'ENDPOINT-GUARD: %d problem(s) in %s (surface %s)\n' "$ERRORS" "$ROOT" "$SURFACE"
  exit 1
fi
printf 'ENDPOINT-GUARD: OK (%s, surface %s)\n' "$ROOT" "$SURFACE"
