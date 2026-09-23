#!/usr/bin/env bash
# Pre-announcement check for a major release of another edition (issue #79).
# Run it against the REAL manifest entry and guide before flipping software.status
# on main (#88/#90); check-endpoints.sh runs it automatically once the entry is
# announced. Track A proves it with the synthetic entry and guide under
# fixtures/synthetic-major/.
#
# Usage: check-major-release.sh <channels/manifest.json> <guide file>
#
# Manifest: software.status prerelease|stable, software.version a major above the
# files-only line, non-empty requirements, a Pages guide URL, auto_update "never",
# no base. Values are read with the same awk parser the shipped updater uses, so an
# entry the updater cannot read fails here too.
# Guide: names the version and has a non-empty section for each thing a user or
# their company must know before consenting.
set -u
MANIFEST=${1:?manifest}
GUIDE=${2:?guide file}
LINE_MAJOR=1
ERRORS=0
err() { ERRORS=$((ERRORS+1)); printf 'MAJOR-RELEASE: %s\n' "$1"; }

manifest_get() { # identical to bin/distill-update.sh
  awk -v sec="$2" -v key="$3" '
    /^[ \t]*"[A-Za-z_]+"[ \t]*:[ \t]*\{/ {
      if (depth == 1) { s = $0; sub(/^[ \t]*"/, "", s); sub(/".*/, "", s); cur = s }
      depth++; next
    }
    /^[ \t]*\{[ \t]*$/ { depth++; next }
    /^[ \t]*\}[ \t]*,?[ \t]*$/ { depth--; if (depth <= 1) cur = ""; next }
    depth == 2 && cur == sec {
      k = $0; sub(/^[ \t]*"/, "", k); sub(/".*/, "", k)
      if (k == key) {
        v = $0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]*,?[ \t]*$/, "", v)
        if (v ~ /^".*"$/) v = substr(v, 2, length(v) - 2)
        print v; exit
      }
    }' "$1" 2>/dev/null | tr -cd '[:print:]' | cut -c1-300
}

[ -f "$MANIFEST" ] || { err "manifest $MANIFEST not found"; exit 1; }
status=$(manifest_get "$MANIFEST" software status)
version=$(manifest_get "$MANIFEST" software version)
req=$(manifest_get "$MANIFEST" software requirements)
guide_url=$(manifest_get "$MANIFEST" software guide)
auto=$(manifest_get "$MANIFEST" software auto_update)
base=$(manifest_get "$MANIFEST" software base)

case "$status" in prerelease|stable) ;; *) err "software.status is '$status'; only prerelease or stable entries are announced" ;; esac
if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$'; then
  err "software.version '$version' is not a version"
elif [ "${version%%.*}" -le "$LINE_MAJOR" ]; then
  err "software.version $version is not a major above the files-only line ($LINE_MAJOR)"
fi
[ "${#req}" -ge 20 ] || err "software.requirements is missing or too short to inform a decision"
printf '%s' "$guide_url" | grep -Eq '^https://tomacco\.github\.io/aura-distill/[A-Za-z0-9._/-]+$' \
  || err "software.guide '$guide_url' is not a page on https://tomacco.github.io/aura-distill/"
[ "$auto" = never ] || err "software.auto_update must be \"never\""
[ -z "$base" ] || err "software.base must not exist"

if [ ! -s "$GUIDE" ]; then
  err "guide $GUIDE not found or empty"
else
  grep -q -- "$version" "$GUIDE" || err "guide does not name version $version"
  for section in "What changes" "Runtime and dependencies" "Processes and startup" \
                 "Network and data destinations" "Storage changes" "Permissions" \
                 "Resource use" "Company approval" "Rollback" "Staying on files-only"; do
    body=$(awk -v h="## $section" '
      tolower($0) == tolower(h) { on = 1; next }
      /^## / { on = 0 }
      on && NF { n++ }
      END { print n + 0 }' "$GUIDE")
    [ "$body" -gt 0 ] || err "guide has no non-empty '## $section' section"
  done
fi

if [ "$ERRORS" -gt 0 ]; then
  printf 'MAJOR-RELEASE: %d problem(s)\n' "$ERRORS"
  exit 1
fi
printf 'MAJOR-RELEASE: OK (v%s, %s)\n' "$version" "$status"
