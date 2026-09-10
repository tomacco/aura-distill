#!/usr/bin/env bash
# check-store.sh — deterministic invariants for a files-only aura-distill store.
#
# Usage: check-store.sh <store-dir> [--before <original-store-dir>]
#
# Prints one "C<n> PASS|FAIL <detail>" line per check group and exits 0 only when
# every group passes. Offline, no profile access, no network. Caps come from the
# environment so the design's numbers can be tuned without editing this file:
#   SPINE_MAX_LINES (80) SPINE_MAX_BYTES (16000) ENTRY_MAX_BYTES (400)
#   FILE_MAX_LINES (60)  FILE_MAX_BYTES (6000)
#
# C1 SPINE budgets            C2 pointers and catalog completeness
# C3 tier-2 budgets/read_with C4 (--before only) lossless migration + archive identity
set -u
export LC_ALL=C

SPINE_MAX_LINES=${SPINE_MAX_LINES:-80}
SPINE_MAX_BYTES=${SPINE_MAX_BYTES:-16000}
ENTRY_MAX_BYTES=${ENTRY_MAX_BYTES:-400}
FILE_MAX_LINES=${FILE_MAX_LINES:-60}
FILE_MAX_BYTES=${FILE_MAX_BYTES:-6000}
TIERS="craft ops profile projects feedback"

STORE=""; BEFORE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --before) BEFORE="$2"; shift 2 ;;
    *) STORE="$1"; shift ;;
  esac
done
[ -n "$STORE" ] && [ -d "$STORE" ] || { echo "usage: $0 <store-dir> [--before <dir>]" >&2; exit 2; }
STORE=$(cd "$STORE" && pwd)
[ -n "$BEFORE" ] && { [ -d "$BEFORE" ] || { echo "no such dir: $BEFORE" >&2; exit 2; }; BEFORE=$(cd "$BEFORE" && pwd); }

RC=0
FAILS=()
fail() { FAILS+=("$1"); }
report() { # group
  if [ ${#FAILS[@]} -eq 0 ]; then echo "$1 PASS"; else
    echo "$1 FAIL"; for f in "${FAILS[@]}"; do echo "    - $f"; done; RC=1; fi
  FAILS=()
}
trim() { sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
tier_files() { # $1 = root
  for t in $TIERS; do [ -d "$1/$t" ] && find "$1/$t" -type f -name '*.md'; done | sed "s|^$1/||" | sort
}
all_known_files() { # tiers + archive + evidence
  { tier_files "$1"; for d in archive evidence; do [ -d "$1/$d" ] && find "$1/$d" -type f -name '*.md' | sed "s|^$1/||"; done; } | sort
}
frontmatter() { awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' "$1"; }

# ── C1: SPINE budgets ────────────────────────────────────────────────────────
SPINE="$STORE/SPINE.md"
if [ ! -f "$SPINE" ]; then fail "SPINE.md missing"; else
  lines=$(wc -l < "$SPINE" | tr -d ' '); bytes=$(wc -c < "$SPINE" | tr -d ' ')
  [ "$lines" -le "$SPINE_MAX_LINES" ] || fail "SPINE has $lines lines (max $SPINE_MAX_LINES)"
  [ "$bytes" -le "$SPINE_MAX_BYTES" ] || fail "SPINE is $bytes bytes (max $SPINE_MAX_BYTES)"
  while IFS= read -r line; do
    n=${#line}
    [ "$n" -le "$ENTRY_MAX_BYTES" ] || fail "entry over $ENTRY_MAX_BYTES bytes ($n): ${line:0:60}..."
  done < <(grep '^- \[' "$SPINE")
  grep -q '](CATALOG.md)' "$SPINE" || fail "SPINE has no catalog line"
fi
report C1

# ── C2: pointers resolve; every file is pointed at and catalogued ────────────
if [ -f "$SPINE" ]; then
  while IFS= read -r p; do [ -f "$STORE/$p" ] || fail "SPINE pointer to missing file: $p"; done \
    < <(grep '^- \[' "$SPINE" | grep -o '](\([^)]*\.md\))' | sed 's/^](//;s/)$//' | sort -u)
  while IFS= read -r p; do grep -Fq -- "($p)" "$SPINE" || fail "active file has no SPINE pointer: $p"; done < <(tier_files "$STORE")
fi
CAT="$STORE/CATALOG.md"
if [ ! -f "$CAT" ]; then fail "CATALOG.md missing"; else
  while IFS= read -r p; do grep -Fq -- "- $p |" "$CAT" || fail "file not in catalog: $p"; done < <(all_known_files "$STORE")
  while IFS= read -r p; do [ -f "$STORE/$p" ] || fail "catalog line points at missing file: $p"; done \
    < <(grep -o '^- [^|]* |' "$CAT" | sed 's/^- //;s/ |$//')
fi
report C2

# ── C3: tier-2 budgets and read_with targets ─────────────────────────────────
while IFS= read -r p; do
  f="$STORE/$p"
  lines=$(wc -l < "$f" | tr -d ' '); bytes=$(wc -c < "$f" | tr -d ' ')
  [ "$lines" -le "$FILE_MAX_LINES" ] || fail "$p has $lines lines (max $FILE_MAX_LINES)"
  [ "$bytes" -le "$FILE_MAX_BYTES" ] || fail "$p is $bytes bytes (max $FILE_MAX_BYTES)"
  rw=$(frontmatter "$f" | grep '^read_with:' | sed 's/^read_with:[[:space:]]*//;s/^\[//;s/\]$//')
  if [ -n "$rw" ]; then
    while IFS= read -r t; do
      [ -z "$t" ] && continue
      [ -f "$STORE/$t" ] || fail "$p read_with target missing: $t"
    done < <(echo "$rw" | tr ',' '\n' | trim)
  fi
done < <(tier_files "$STORE")
report C3

# ── C4: lossless migration (only with --before) ──────────────────────────────
if [ -n "$BEFORE" ]; then
  tmp=$(mktemp)
  while IFS= read -r p; do
    : > "$tmp"
    for cand in "$STORE/$p" "$STORE/evidence/$p" "$STORE/archive/$p"; do
      [ -f "$cand" ] && trim < "$cand" >> "$tmp"
    done
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      grep -Fxq -- "$line" "$tmp" || fail "line lost from $p: ${line:0:70}"
    done < <(trim < "$BEFORE/$p")
    if grep -q '^lifecycle: pinned' "$BEFORE/$p" && [ ! -f "$STORE/$p" ]; then fail "pinned file was moved: $p"; fi
  done < <(tier_files "$BEFORE")
  # archived files are byte-identical to their originals
  if [ -d "$STORE/archive" ]; then
    while IFS= read -r p; do
      orig="$BEFORE/${p#archive/}"
      if [ ! -f "$orig" ]; then fail "archived file has no original: $p"
      elif [ "$(sha "$STORE/$p")" != "$(sha "$orig")" ]; then fail "archived file differs from original: $p"; fi
    done < <(find "$STORE/archive" -type f -name '*.md' | sed "s|^$STORE/||")
  fi
  # protected wording survives in an ACTIVE or ARCHIVED file (evidence does not count)
  : > "$tmp"
  { tier_files "$STORE"; [ -d "$STORE/archive" ] && find "$STORE/archive" -type f -name '*.md' | sed "s|^$STORE/||"; } \
    | while IFS= read -r p; do trim < "$STORE/$p"; done > "$tmp"
  while IFS= read -r p; do
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      grep -Fxq -- "$line" "$tmp" || fail "protected line not in active/archive ($p): ${line:0:70}"
    done < <(grep -E '\[(NON-NEGOTIABLE|DIRECTIVE)\]' "$BEFORE/$p" | trim)
  done < <(tier_files "$BEFORE")
  # every original SPINE hook survives somewhere as a substring
  if [ -f "$BEFORE/SPINE.md" ]; then
    while IFS= read -r line; do
      hook=$(printf '%s' "$line" | sed 's/^- \[[^]]*\]([^)]*) *\(—\|--\) *//')
      [ -n "$hook" ] || continue
      grep -rFq -- "$hook" "$STORE" || fail "SPINE hook lost: ${hook:0:70}"
    done < <(grep '^- \[' "$BEFORE/SPINE.md")
  fi
  rm -f "$tmp"
  report C4
fi

exit $RC
