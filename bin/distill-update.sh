#!/usr/bin/env bash
# aura-distill-updater (files-only line 1). Decisions: docs/adr/0001 and docs/adr/0002.
#
# The only code that replaces installed aura-distill files after installation.
# The /distill dispatcher runs it instead of composing its own download commands.
# It never executes anything it downloads, never installs a different major
# version, and never touches knowledge files (SPINE, tiers, preferences, inbox).
#
# Usage: distill-update.sh auto | check | apply
#   auto   apply when the Auto-update preference is on, otherwise behave like check
#   check  report only; the one thing it writes is .major-notice (a notice was shown)
#          (a same-version repair is reported as AVAILABLE, not performed)
#   apply  download everything to a temp dir, validate every file, then replace
#          the installed files; any failure leaves every installed file untouched
#
# Output: the first line is exactly one of
#   CURRENT <version> <channel>
#   AVAILABLE <installed> <target> <channel>
#   UPDATED <installed> <target> <channel>
#   REPAIRED <version> <channel>   (same version re-installed: an older updater had
#                                   left the store path unresolved in the files)
#   BLOCKED <channel> <reason>
# followed by zero or more "NOTICE: ..." lines meant to be shown to the user as text.
#
# Channel: <store>/.channel holds "stable" (default when absent) or "beta".
#   stable  version from <raw>/main/VERSION, files from <raw>/main/  (the legacy
#           endpoint set, frozen by ADR 0001; never beta, never a software major)
#   beta    the manifest at <raw>/beta/1.2/channels/manifest.json names one
#           prerelease tag; files come from <raw>/<tag>/ (immutable once cut)
#
# Test/mirror overrides: AURA_DISTILL_RAW_ROOT (default
# https://raw.githubusercontent.com/tomacco/aura-distill) and
# AURA_DISTILL_CHANNEL_MANIFEST (beta manifest URL or local path).
set -u

LINE_MAJOR=1
# Built by concatenation so this file never contains the marker it rejects.
SOFTWARE_MARKER="AURA_SOFTWARE_""MAJOR_PAYLOAD"
PLACEHOLDER="{DISTILL""_DIR}"
RAW_ROOT="${AURA_DISTILL_RAW_ROOT:-https://raw.githubusercontent.com/tomacco/aura-distill}"
BETA_MANIFEST="${AURA_DISTILL_CHANNEL_MANIFEST:-$RAW_ROOT/beta/1.2/channels/manifest.json}"
GUIDE_RE='^https://tomacco\.github\.io/aura-distill/[A-Za-z0-9._/-]+$'
TAG_RE='^v[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$'
VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$'

MODE="${1:-}"
case "$MODE" in auto|check|apply) ;; *) echo "usage: distill-update.sh auto|check|apply" >&2; exit 64 ;; esac

# Run from a temporary copy so that replacing this very file (self-update) never
# races the running interpreter, and works on Windows where open files are locked.
if [ -z "${AURA_UPDATER_SELF:-}" ]; then
  self_dir=$(cd "$(dirname "$0")" && pwd)
  copy=$(mktemp "${TMPDIR:-/tmp}/aura-distill-updater.XXXXXX") || { echo "BLOCKED unknown cannot create a temporary file"; exit 0; }
  cat "$0" > "$copy"
  AURA_UPDATER_SELF="$self_dir/$(basename "$0")" AURA_UPDATER_COPY="$copy" exec bash "$copy" "$@"
fi
# Only ever delete the temporary copy, never the installed script (for example if
# AURA_UPDATER_SELF leaked into the caller's environment).
SELF_COPY=""
[ "${AURA_UPDATER_COPY:-}" = "$0" ] && SELF_COPY=$0
trap 'rm -f "$SELF_COPY"' EXIT

STORE=$(cd "$(dirname "$AURA_UPDATER_SELF")/.." && pwd)
# Git Bash on Windows: write C:/Users/... (accepted by bash and by the client's file
# tools) into the installed files, not the MSYS form /c/Users/...
if command -v cygpath >/dev/null 2>&1; then STORE=$(cygpath -m "$STORE"); fi
CMD_FILE=$(head -1 "$STORE/.command-path" 2>/dev/null | LC_ALL=C tr -d '\357\273\277\r' || true)
# A recorded path whose directory does not exist here (a store synced from another
# machine or user) falls back to the default instead of blocking every update.
case "$CMD_FILE" in */distill.md) [ -d "$(dirname "$CMD_FILE")" ] || CMD_FILE="" ;; *) CMD_FILE="" ;; esac
[ -n "$CMD_FILE" ] || CMD_FILE="$HOME/.claude/commands/distill.md"
# Strip whitespace, CR and a UTF-8 byte-order mark (Windows PowerShell 5.1 writes one).
read_meta() { LC_ALL=C tr -d '\357\273\277[:space:]' 2>/dev/null < "$1" || true; }
CHANNEL=$(read_meta "$STORE/.channel")
[ "$CHANNEL" = beta ] || CHANNEL=stable
INSTALLED=$(read_meta "$STORE/.version")

WORK=$(mktemp -d "${TMPDIR:-/tmp}/aura-distill-update.XXXXXX") || { echo "BLOCKED $CHANNEL cannot create a temporary directory"; exit 0; }
trap 'rm -rf "$WORK"; rm -f "$SELF_COPY"' EXIT

fetch() { # <url-or-local-path> <dest>
  if [ -f "$1" ]; then cp "$1" "$2"; else curl -fsSL --max-time 30 "$1" -o "$2" 2>/dev/null; fi
}

# Reads "key": "value" from one top-level object of a manifest written one key per
# line (the layout tests/updater-compat/check-endpoints.sh enforces).
manifest_get() { # <file> <section> <key>
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

major_of() { printf '%s' "${1%%.*}"; }

NOTICES=""
# The software edition is announced, never fetched: only version, requirements and
# guide are read, and the guide URL is printed as text. Shown once per
# (version, requirements, guide); a change to any of them shows it again.
collect_notice() { # <manifest file>
  local m=$1 status version req guide key
  [ -s "$m" ] || return 0
  status=$(manifest_get "$m" software status)
  case "$CHANNEL:$status" in stable:stable|beta:stable|beta:prerelease) ;; *) return 0 ;; esac
  version=$(manifest_get "$m" software version)
  req=$(manifest_get "$m" software requirements)
  guide=$(manifest_get "$m" software guide)
  printf '%s' "$version" | grep -Eq "$VERSION_RE" || return 0
  [ "$(major_of "$version")" -gt "$LINE_MAJOR" ] 2>/dev/null || return 0
  [ -n "$req" ] || return 0
  printf '%s' "$guide" | grep -Eq "$GUIDE_RE" || return 0
  key="$version $(printf '%s|%s|%s' "$version" "$req" "$guide" | cksum | cut -d' ' -f1)"
  [ "$(cat "$STORE/.major-notice" 2>/dev/null)" = "$key" ] && return 0
  NOTICES="NOTICE: aura-distill: a separate software edition (v$version) is available. Auto-update does not install it and will not.
NOTICE: It requires: $req.
NOTICE: Your files-only installation stays supported and unchanged. If you want it, read $guide first and run its installer yourself. No reply is needed."
  printf '%s\n' "$key" > "$STORE/.major-notice.tmp" && mv "$STORE/.major-notice.tmp" "$STORE/.major-notice"
}

finish() { # <status line>
  printf '%s\n' "$1"
  [ -z "$NOTICES" ] || printf '%s\n' "$NOTICES"
  exit 0
}

# ---------- resolve the target release for this channel ----------
TARGET=""; BASE=""
if [ "$CHANNEL" = stable ]; then
  BASE="$RAW_ROOT/main"
  fetch "$RAW_ROOT/main/channels/manifest.json" "$WORK/manifest.json" || rm -f "$WORK/manifest.json"
  collect_notice "$WORK/manifest.json"
  fetch "$BASE/VERSION" "$WORK/VERSION" || finish "BLOCKED $CHANNEL could not read the latest version (offline or unavailable)"
  TARGET=$(tr -d '[:space:]' < "$WORK/VERSION")
  printf '%s' "$TARGET" | grep -Eq "$VERSION_RE" || finish "BLOCKED $CHANNEL the published version is not a valid version string"
  case "$TARGET" in *-*) finish "BLOCKED $CHANNEL the stable endpoint reports a prerelease ($TARGET); refusing" ;; esac
else
  fetch "$BETA_MANIFEST" "$WORK/manifest.json" || finish "BLOCKED $CHANNEL could not read the beta channel manifest (offline or unavailable)"
  collect_notice "$WORK/manifest.json"
  status=$(manifest_get "$WORK/manifest.json" beta status)
  case "$status" in
    prerelease|stable) ;;
    unpublished) finish "BLOCKED $CHANNEL no beta release is published yet" ;;
    closed) finish "BLOCKED $CHANNEL the beta channel is closed; return to stable with the installer's --channel stable" ;;
    *) finish "BLOCKED $CHANNEL the beta channel manifest is missing or malformed" ;;
  esac
  tag=$(manifest_get "$WORK/manifest.json" beta tag)
  TARGET=$(manifest_get "$WORK/manifest.json" beta version)
  printf '%s' "$tag" | grep -Eq "$TAG_RE" || finish "BLOCKED $CHANNEL the beta manifest names an invalid tag"
  [ "${tag#v}" = "$TARGET" ] || finish "BLOCKED $CHANNEL the beta manifest is inconsistent (tag $tag, version $TARGET)"
  BASE="$RAW_ROOT/$tag"
fi

if [ "$(major_of "$TARGET")" != "$LINE_MAJOR" ]; then
  finish "BLOCKED $CHANNEL v$TARGET is a different major version; updates never cross a major, it needs its own installer and your explicit consent"
fi

if [ "$CHANNEL" = beta ]; then
  fetch "$BASE/VERSION" "$WORK/VERSION" || finish "BLOCKED $CHANNEL could not read $tag (offline or unavailable)"
  served=$(tr -d '[:space:]' < "$WORK/VERSION")
  [ "$served" = "$TARGET" ] || finish "BLOCKED $CHANNEL the beta release is inconsistent (manifest $TARGET, tag serves ${served:-nothing})"
fi

# An older updater copied files without resolving the store placeholder (ADR 0001,
# latent defect 2). Re-installing the same version repairs them; it is not an upgrade,
# so it runs regardless of the Auto-update preference.
REPAIR=0
for t in "$CMD_FILE" "$STORE/distill-process.md" "$STORE/distill-monitor.md"; do
  grep -qF "$PLACEHOLDER" "$t" 2>/dev/null && REPAIR=1
done
if [ "$TARGET" = "$INSTALLED" ]; then
  [ "$REPAIR" = 1 ] || finish "CURRENT $TARGET $CHANNEL"
  [ "$MODE" = check ] && finish "AVAILABLE ${INSTALLED:-unknown} $TARGET $CHANNEL"
  MODE=apply
fi

if [ "$MODE" = auto ]; then
  if awk '/^## /{on=($0 ~ /^## Auto-update/)} on && /^[ \t]*-[ \t]*enabled:[ \t]*true[ \t]*$/{found=1} END{exit !found}' \
       "$STORE/feedback/preferences.md" 2>/dev/null; then
    MODE=apply
  else
    MODE=check
  fi
fi
[ "$MODE" = check ] && finish "AVAILABLE ${INSTALLED:-unknown} $TARGET $CHANNEL"

# ---------- apply: stage, validate all, then replace ----------
mkdir -p "$WORK/stage/bin"
store_esc=$(printf '%s' "$STORE" | sed 's/[&|\\]/\\&/g')
for f in distill.md distill-process.md distill-monitor.md bin/distill-update.sh; do
  raw="$WORK/stage/$f.raw"
  fetch "$BASE/$f" "$raw" || finish "BLOCKED $CHANNEL download of $f failed; nothing was changed"
  [ -s "$raw" ] || finish "BLOCKED $CHANNEL $f was empty; nothing was changed"
  if grep -q "$SOFTWARE_MARKER" "$raw"; then
    finish "BLOCKED $CHANNEL $f is a software-edition payload; the files-only updater never installs it; nothing was changed"
  fi
  if [ "$f" = bin/distill-update.sh ]; then
    { sed -n '2p' "$raw" | grep -q '^# aura-distill-updater' && bash -n "$raw" 2>/dev/null; } || finish "BLOCKED $CHANNEL $f failed validation; nothing was changed"
    mv "$raw" "$WORK/stage/$f"
  else
    head -1 "$raw" | grep -q '^# ' || finish "BLOCKED $CHANNEL $f failed validation; nothing was changed"
    sed "s|$PLACEHOLDER|$store_esc|g" "$raw" > "$WORK/stage/$f" && rm -f "$raw"
  fi
done

mkdir -p "$(dirname "$CMD_FILE")" "$STORE/bin" "$STORE/data" "$STORE/inbox" || finish "BLOCKED $CHANNEL cannot create directories; nothing was changed"
# Temp names next to each target (same filesystem), unique per process so two
# sessions updating one store cannot rename each other's files; then one checked
# rename per file. The status line is only UPDATED if every rename succeeded.
N=".aura-new.$$"
cleanup_new() { rm -f "$CMD_FILE$N" "$STORE/distill-process.md$N" "$STORE/distill-monitor.md$N" "$STORE/bin/distill-update.sh$N" "$STORE/.version$N"; }
cp "$WORK/stage/distill.md" "$CMD_FILE$N" \
  && cp "$WORK/stage/distill-process.md" "$STORE/distill-process.md$N" \
  && cp "$WORK/stage/distill-monitor.md" "$STORE/distill-monitor.md$N" \
  && cp "$WORK/stage/bin/distill-update.sh" "$STORE/bin/distill-update.sh$N" \
  && printf '%s\n' "$TARGET" > "$STORE/.version$N" \
  || { cleanup_new; finish "BLOCKED $CHANNEL cannot write the new files; nothing was changed"; }
chmod +x "$STORE/bin/distill-update.sh$N" 2>/dev/null || true
for pair in "$CMD_FILE" "$STORE/distill-process.md" "$STORE/distill-monitor.md" "$STORE/bin/distill-update.sh" "$STORE/.version"; do
  if ! mv -f "$pair$N" "$pair" 2>/dev/null; then
    cleanup_new
    finish "BLOCKED $CHANNEL replacing $(basename "$pair") failed; the installation may be partially updated, run the installer to repair it"
  fi
done
[ "$TARGET" = "$INSTALLED" ] && finish "REPAIRED $TARGET $CHANNEL"
finish "UPDATED ${INSTALLED:-unknown} $TARGET $CHANNEL"
