#!/usr/bin/env bash
# check-store.sh — deterministic invariants for a files-only aura-distill store.
#
# Usage: check-store.sh <store-dir> [--before <original-store-dir>]
#
# Prints one "C<n> PASS|FAIL" line per check group (with indented reasons) and
# exits 0 only when every group passes. Offline, no profile access, no network,
# carriage returns ignored, GNU and BSD toolchains. Caps come from the environment:
#   SPINE_MAX_LINES (80) SPINE_MAX_BYTES (16000) ENTRY_MAX_BYTES (400)
#   FILE_MAX_LINES (60)  FILE_MAX_BYTES (6000)
#
# C1 SPINE budgets
# C2 pointers, catalog completeness and counts, evidence_for, collisions, ledger checksums
# C3 tier-2 budgets, read_with (inline list, targets, no local/), split_from, oversize
# C4 (--before only) multiset line conservation, protected blocks, archive identity,
#    legacy identity, pins, SPINE-hook survival
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
if [ -n "$BEFORE" ]; then
  [ -d "$BEFORE" ] || { echo "no such dir: $BEFORE" >&2; exit 2; }
  BEFORE=$(cd "$BEFORE" && pwd)
fi

RC=0
FAILS=()
fail() { FAILS+=("$1"); }
report() {
  if [ ${#FAILS[@]} -eq 0 ]; then echo "$1 PASS"; else
    echo "$1 FAIL"; for f in "${FAILS[@]}"; do echo "    - $f"; done; RC=1; fi
  FAILS=()
}
nocr() { tr -d '\r'; }
trim() { nocr | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
count_lines() { nocr < "$1" | grep -c '' ; }
count_bytes() { wc -c < "$1" | tr -d ' '; }
tier_files() { # $1 = root  → relative paths
  for t in $TIERS; do [ -d "$1/$t" ] && find "$1/$t" -type f -name '*.md'; done | sed "s|^$1/||" | sort
}
archive_files() { [ -d "$1/archive" ] && find "$1/archive" -type f -name '*.md' ! -name 'LEDGER.md' | sed "s|^$1/||" | sort; return 0; }
evidence_files() { [ -d "$1/evidence" ] && find "$1/evidence" -type f -name '*.md' | sed "s|^$1/||" | sort; return 0; }
frontmatter() { nocr < "$1" | awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}'; }
fm_value() { frontmatter "$1" | grep "^$2:" | head -1 | sed "s/^$2:[[:space:]]*//"; }
catalog_row() { grep -F -- "- $2 |" "$1" | head -1 | nocr; }
is_legacy() { catalog_row "$CAT" "$1" | grep -q '| legacy'; }

# ── C1: SPINE budgets ────────────────────────────────────────────────────────
SPINE="$STORE/SPINE.md"
if [ ! -f "$SPINE" ]; then fail "SPINE.md missing"; else
  lines=$(count_lines "$SPINE"); bytes=$(count_bytes "$SPINE")
  [ "$lines" -le "$SPINE_MAX_LINES" ] || fail "SPINE has $lines lines (max $SPINE_MAX_LINES)"
  [ "$bytes" -le "$SPINE_MAX_BYTES" ] || fail "SPINE is $bytes bytes (max $SPINE_MAX_BYTES)"
  while IFS= read -r line; do
    n=${#line}
    [ "$n" -le "$ENTRY_MAX_BYTES" ] || fail "entry over $ENTRY_MAX_BYTES bytes ($n): ${line:0:60}..."
  done < <(nocr < "$SPINE" | grep '^- \[')
  grep -q '](CATALOG.md)' "$SPINE" || fail "SPINE has no catalog line"
fi
report C1

# ── C2: pointers, catalog, evidence_for, collisions, ledger ──────────────────
if [ -f "$SPINE" ]; then
  while IFS= read -r p; do [ -f "$STORE/$p" ] || fail "SPINE pointer to missing file: $p"; done \
    < <(nocr < "$SPINE" | grep '^- \[' | grep -o '](\([^)]*\.md\))' | sed 's/^](//;s/)$//' | sort -u)
  while IFS= read -r p; do grep -Fq -- "($p)" "$SPINE" || fail "active file has no SPINE pointer: $p"; done < <(tier_files "$STORE")
fi
CAT="$STORE/CATALOG.md"
LEDGER="$STORE/archive/LEDGER.md"
if [ ! -f "$CAT" ]; then fail "CATALOG.md missing"; else
  while IFS= read -r p; do grep -Fq -- "- $p |" "$CAT" || fail "file not in catalog: $p"; done \
    < <({ tier_files "$STORE"; archive_files "$STORE"; evidence_files "$STORE"; } | sort)
  while IFS= read -r p; do [ -f "$STORE/$p" ] || fail "catalog line points at missing file: $p"; done \
    < <(nocr < "$CAT" | grep -o '^- [^|]* |' | sed 's/^- //;s/ |$//')
  # evidence counts and evidence_for
  while IFS= read -r e; do
    n=$(nocr < "$STORE/$e" | grep -c '^- ')
    catalog_row "$CAT" "$e" | grep -Fq -- "| $n entries" || fail "catalog count wrong for $e (file has $n entries)"
    target=$(fm_value "$STORE/$e" evidence_for)
    if [ -z "$target" ]; then fail "$e has no evidence_for"
    elif [ ! -f "$STORE/$target" ] && [ ! -f "$STORE/archive/$target" ]; then fail "orphan evidence: $e (evidence_for $target is neither active nor archived)"; fi
  done < <(evidence_files "$STORE")
  # archived rows: ledger line with matching sha256, from + hook; legacy rows exempt
  while IFS= read -r a; do
    if is_legacy "$a"; then continue; fi
    catalog_row "$CAT" "$a" | grep -q '| from ' || fail "archived row lacks 'from': $a"
    catalog_row "$CAT" "$a" | grep -q '| hook: ' || fail "archived row lacks 'hook': $a"
    if [ ! -f "$LEDGER" ]; then fail "archive/LEDGER.md missing but $a is not legacy"; continue; fi
    lsha=$(nocr < "$LEDGER" | grep -F -- "| to: $a |" | tail -1 | grep -o 'sha256: [0-9a-f]*' | sed 's/sha256: //')
    if [ -z "$lsha" ]; then fail "no ledger line for archived file: $a"
    elif [ "$lsha" != "$(sha "$STORE/$a")" ]; then fail "ledger sha256 does not match archived file: $a"; fi
  done < <(archive_files "$STORE")
fi
# collisions: a path may not be both active and archived
while IFS= read -r p; do [ -f "$STORE/archive/$p" ] && fail "path exists both active and archived: $p"; done < <(tier_files "$STORE")
report C2

# ── C3: tier-2 budgets, read_with, split_from, oversize ──────────────────────
while IFS= read -r p; do
  f="$STORE/$p"
  lines=$(count_lines "$f"); bytes=$(count_bytes "$f")
  [ "$lines" -le "$FILE_MAX_LINES" ] || fail "$p has $lines lines (max $FILE_MAX_LINES)"
  if [ -z "$(fm_value "$f" oversize)" ]; then
    [ "$bytes" -le "$FILE_MAX_BYTES" ] || fail "$p is $bytes bytes (max $FILE_MAX_BYTES; declare oversize: <reason> to exempt)"
  fi
  if frontmatter "$f" | grep -q '^read_with:'; then
    rw=$(fm_value "$f" read_with)
    case "$rw" in
      \[*\]) rw=${rw#\[}; rw=${rw%\]}
        while IFS= read -r t; do
          [ -z "$t" ] && continue
          case "$t" in local/*) fail "$p read_with into local/ overlay: $t"; continue ;; esac
          [ -f "$STORE/$t" ] || fail "$p read_with target missing: $t"
        done < <(printf '%s\n' "$rw" | tr ',' '\n' | trim) ;;
      *) fail "$p read_with must be an inline list [a.md, b.md]" ;;
    esac
  fi
  sf=$(fm_value "$f" split_from)
  [ -n "$sf" ] && [ ! -f "$STORE/$sf" ] && fail "$p split_from target missing: $sf"
done < <(tier_files "$STORE")
report C3

# ── C4: lossless migration (only with --before) ──────────────────────────────
if [ -n "$BEFORE" ]; then
  cand=$(mktemp); protected_pool=$(mktemp)
  # candidate text for original file p: after/p, its evidence twin, its archived copy,
  # its split children (split_from: p) and their evidence twins
  candidates_for() {
    local p="$1"; : > "$cand"
    for c in "$STORE/$p" "$STORE/evidence/$p" "$STORE/archive/$p"; do [ -f "$c" ] && trim < "$c" >> "$cand"; done
    while IFS= read -r child; do
      [ "$(fm_value "$STORE/$child" split_from)" = "$p" ] || continue
      trim < "$STORE/$child" >> "$cand"; [ -f "$STORE/evidence/$child" ] && trim < "$STORE/evidence/$child" >> "$cand"
    done < <(tier_files "$STORE")
  }
  while IFS= read -r p; do
    candidates_for "$p"
    # multiset conservation: each distinct line must appear at least as often as before
    while read -r k line; do
      [ -z "$line" ] && continue
      have=$(grep -Fxc -- "$line" "$cand")
      [ "$have" -ge "$k" ] || fail "line lost from $p (before x$k, after x$have): ${line:0:70}"
    done < <(trim < "$BEFORE/$p" | grep -v '^$' | sort | uniq -c | sed 's/^ *//')
    if grep -q '^lifecycle: pinned' "$BEFORE/$p" && [ ! -f "$STORE/$p" ]; then fail "pinned file was moved: $p"; fi
  done < <(tier_files "$BEFORE")
  # archived files: non-legacy must equal the original tier file; legacy must equal its own before copy
  while IFS= read -r a; do
    rel=${a#archive/}
    if [ -f "$BEFORE/$a" ]; then
      [ "$(sha "$STORE/$a")" = "$(sha "$BEFORE/$a")" ] || fail "legacy archive file changed: $a"
    elif [ ! -f "$BEFORE/$rel" ]; then fail "archived file has no original: $a"
    elif [ "$(sha "$STORE/$a")" != "$(sha "$BEFORE/$rel")" ]; then fail "archived file differs from original: $a"; fi
  done < <(archive_files "$STORE")
  # protected bullet + its indented block must survive in an ACTIVE or ARCHIVED file (evidence does not count)
  { tier_files "$STORE"; archive_files "$STORE"; } | while IFS= read -r p; do trim < "$STORE/$p"; done > "$protected_pool"
  while IFS= read -r p; do
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      grep -Fxq -- "$line" "$protected_pool" || fail "protected block line not in active/archive ($p): ${line:0:70}"
    done < <(nocr < "$BEFORE/$p" | awk '
      /^- .*\[(NON-NEGOTIABLE|DIRECTIVE)\]/ {inblock=1; print; next}
      inblock && /^[ \t]+[^ \t]/ {print; next}
      {inblock=0}' | trim)
  done < <(tier_files "$BEFORE")
  # every original SPINE hook survives as a substring in SPINE, tier files, archive or catalog (never data/ or evidence)
  if [ -f "$BEFORE/SPINE.md" ]; then
    scope=(); [ -f "$STORE/SPINE.md" ] && scope+=("$STORE/SPINE.md"); [ -f "$STORE/CATALOG.md" ] && scope+=("$STORE/CATALOG.md")
    for d in $TIERS archive; do [ -d "$STORE/$d" ] && scope+=("$STORE/$d"); done
    while IFS= read -r line; do
      hook=$(printf '%s' "$line" | sed 's/^- \[[^]]*\]([^)]*)//' | sed 's/^ *— *//; s/^ *-- *//')
      [ -n "$hook" ] || continue
      grep -rFq -- "$hook" "${scope[@]}" || fail "SPINE hook lost: ${hook:0:70}"
    done < <(nocr < "$BEFORE/SPINE.md" | grep '^- \[')
  fi
  rm -f "$cand" "$protected_pool"
  report C4
fi

exit $RC
