#!/usr/bin/env bash
# check-store.sh — deterministic invariants for a files-only aura-distill store.
#
# Usage: check-store.sh <store-dir> [--before <original-store-dir>]
#
# Prints one "C<n> PASS|FAIL" line per check group (with indented reasons) and
# exits 0 only when every group passes. Offline, no profile access, no network,
# GNU and BSD toolchains. Line comparisons and line counts ignore carriage
# returns; checksums and byte counts are over raw bytes (byte identity means bytes).
# Caps come from the environment:
#   SPINE_MAX_LINES (80) SPINE_MAX_BYTES (16000) ENTRY_MAX_BYTES (400)
#   FILE_MAX_LINES (60)  FILE_MAX_BYTES (6000)
#
# C1 SPINE budgets
# C2 pointers; catalog equals tree (presence, validated date, pinned, evidence counts,
#    archived rows' from/hook); evidence_for; collisions; ledger last-event agreement + sha256
# C3 tier-2 budgets, read_with (inline list, targets, no local/), split_from, oversize
# C4 (--before only) multiset line conservation, protected blocks, archive identity,
#    legacy identity, pins, SPINE-hook survival; protected = bullet+block or heading section
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
newest_stamp() { nocr < "$1" | grep -oE 'last_(validated|updated): *[0-9]{4}-[0-9]{2}-[0-9]{2}' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | tail -1; }
catalog_row() { grep -F -- "- $2 |" "$1" | head -1 | nocr; }
is_legacy() { case "${1#archive/}" in */*) return 1 ;; *) return 0 ;; esac; }   # structural: flat under archive/ = legacy
field() { printf '%s' "$1" | sed "s/.*| $2: //; s/ |.*//" | sed 's/[[:space:]]*$//'; }   # field <line> <name>
# ledger_last_events: "<path> <archive|restore>" for the newest event per path
# (a top-level function: bash 3.2 cannot parse a case statement inside a process substitution)
ledger_last_events() {
  nocr < "$LEDGER" | grep -E '^- [0-9-]+ (archive|restore)' | while IFS= read -r l; do
    e=$(printf '%s' "$l" | awk '{print $3}'); to=$(field "$l" to)
    if [ "$e" = "archive" ]; then printf '%s %s\n' "${to#archive/}" archive
    elif [ "$e" = "restore" ]; then printf '%s %s\n' "$to" restore; fi
  done | awk '{last[$1]=$2} END{for (k in last) print k, last[k]}'
}
hook_of_entry() { printf '%s' "$1" | sed -E 's/^- \[[^]]*\]\([^)]*\)( *\+ *\[[^]]*\]\([^)]*\))*//' | sed 's/^ *— *//; s/^ *-- *//'; }

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

# ── C2: pointers, catalog equals tree, evidence_for, collisions, ledger ──────
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
  # active rows: validated date = newest stamp; pinned flag = lifecycle: pinned
  while IFS= read -r p; do
    row=$(catalog_row "$CAT" "$p"); [ -n "$row" ] || continue
    stamp=$(newest_stamp "$STORE/$p")
    if [ -n "$stamp" ]; then printf '%s' "$row" | grep -Fq -- "| validated $stamp" || fail "catalog validated date wrong for $p (newest stamp $stamp)"
    else printf '%s' "$row" | grep -q '| validated ' && fail "catalog claims a validated date for undated file $p"; fi
    if [ "$(fm_value "$STORE/$p" lifecycle)" = "pinned" ]; then printf '%s' "$row" | grep -q '| pinned' || fail "catalog row lacks pinned for $p"
    else printf '%s' "$row" | grep -q '| pinned' && fail "catalog row says pinned but $p is not"; fi
  done < <(tier_files "$STORE")
  # evidence counts and evidence_for
  while IFS= read -r e; do
    n=$(nocr < "$STORE/$e" | grep -c '^- ')
    catalog_row "$CAT" "$e" | grep -Fq -- "| $n entries" || fail "catalog count wrong for $e (file has $n entries)"
    target=$(fm_value "$STORE/$e" evidence_for)
    if [ -z "$target" ]; then fail "$e has no evidence_for"
    elif [ "$target" != "${e#evidence/}" ]; then fail "evidence_for disagrees with the twin's path: $e says $target"
    elif [ ! -f "$STORE/$target" ] && [ ! -f "$STORE/archive/$target" ]; then fail "orphan evidence: $e (evidence_for $target is neither active nor archived)"; fi
  done < <(evidence_files "$STORE")
  # archived rows: from + hook, hook equals the ledger's spine-entry hook, sha256 from the last archive event
  while IFS= read -r a; do
    row=$(catalog_row "$CAT" "$a")
    if is_legacy "$a"; then
      printf '%s' "$row" | grep -q '| legacy' || fail "flat archive file must be labelled legacy in the catalog: $a"
      continue
    fi
    printf '%s' "$row" | grep -q '| legacy' && fail "nested archive file labelled legacy: $a"
    printf '%s' "$row" | grep -q '| from ' || fail "archived row lacks 'from': $a"
    printf '%s' "$row" | grep -q '| hook: ' || fail "archived row lacks 'hook': $a"
    if [ ! -f "$LEDGER" ]; then fail "archive/LEDGER.md missing but $a is not legacy"; continue; fi
    ev=$(nocr < "$LEDGER" | grep -F -- "| to: $a |" | grep -E '^- [0-9-]+ archive ' | tail -1)
    if [ -z "$ev" ]; then fail "no ledger archive event for: $a"; continue; fi
    lsha=$(printf '%s' "$ev" | grep -o 'sha256: [0-9a-f]*' | sed 's/sha256: //')
    [ "$lsha" = "$(sha "$STORE/$a")" ] || fail "ledger sha256 does not match archived file: $a"
    lhook=$(hook_of_entry "$(printf '%s' "$ev" | sed 's/.*| spine-entry: //')" | sed 's/[[:space:]]*$//')
    chook=$(printf '%s' "$row" | sed 's/.*| hook: //' | sed 's/[[:space:]]*$//')
    [ "$lhook" = "$chook" ] || fail "catalog hook differs from ledger spine-entry hook: $a"
  done < <(archive_files "$STORE")
fi
# ledger last event per path must agree with the tree
if [ -f "$LEDGER" ]; then
  while read -r x ev; do
    case "$ev" in
      archive) { [ -f "$STORE/archive/$x" ] && [ ! -f "$STORE/$x" ]; } || fail "ledger says archived but tree disagrees: $x" ;;
      restore) { [ -f "$STORE/$x" ] && [ ! -f "$STORE/archive/$x" ]; } || fail "ledger says restored but tree disagrees: $x" ;;
      *) fail "unknown ledger event '$ev' for $x" ;;
    esac
  done < <(ledger_last_events | sort)
fi
# catalog rebuilt stamp must not predate the newest ledger event
if [ -f "$LEDGER" ] && [ -f "$CAT" ]; then
  rebuilt=$(nocr < "$CAT" | grep -oE 'rebuilt: [0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 | sed 's/rebuilt: //')
  newest=$(nocr < "$LEDGER" | grep -oE '^- [0-9]{4}-[0-9]{2}-[0-9]{2}' | sed 's/^- //' | sort | tail -1)
  if [ -z "$rebuilt" ]; then fail "catalog has no rebuilt: stamp"
  elif [ -n "$newest" ] && [ "$newest" \> "$rebuilt" ]; then fail "catalog stale: rebuilt $rebuilt but newest ledger event is $newest"; fi
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
      trim < "$STORE/$child" >> "$cand"
      rel=${child#archive/}; [ -f "$STORE/evidence/$rel" ] && trim < "$STORE/evidence/$rel" >> "$cand"
    done < <({ tier_files "$STORE"; archive_files "$STORE"; })
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
    if grep -qE '\[NON-NEGOTIABLE[^]]*\]' "$BEFORE/$p" && [ -f "$STORE/archive/$p" ]; then fail "file carrying [NON-NEGOTIABLE] was archived: $p"; fi
  done < <(tier_files "$BEFORE")
  # evidence twins are append-only: every line of a pre-existing twin survives in the same twin
  while IFS= read -r e; do
    if [ ! -f "$STORE/$e" ]; then fail "evidence twin deleted: $e"; continue; fi
    trim < "$STORE/$e" > "$cand"
    while read -r k line; do
      [ -z "$line" ] && continue
      have=$(grep -Fxc -- "$line" "$cand")
      [ "$have" -ge "$k" ] || fail "line lost from $e (before x$k, after x$have): ${line:0:70}"
    done < <(trim < "$BEFORE/$e" | grep -v '^$' | sort | uniq -c | sed 's/^ *//')
  done < <(evidence_files "$BEFORE")
  # nothing leaves the archive: every pre-existing archive file still exists
  while IFS= read -r a; do [ -f "$STORE/$a" ] || fail "archive file deleted: $a"; done < <(archive_files "$BEFORE")
  # archived files: non-legacy must equal the original tier file; legacy must equal its own before copy
  while IFS= read -r a; do
    rel=${a#archive/}
    if [ -f "$BEFORE/$a" ]; then
      [ "$(sha "$STORE/$a")" = "$(sha "$BEFORE/$a")" ] || fail "legacy archive file changed: $a"
    elif [ ! -f "$BEFORE/$rel" ]; then fail "archived file has no original: $a"
    elif [ "$(sha "$STORE/$a")" != "$(sha "$BEFORE/$rel")" ]; then
      # edited after migration and before the move is legitimate ONLY if the ledger checksum matches the file
      # (its original lines are then covered by the conservation check above)
      lsha=$([ -f "$LEDGER" ] && nocr < "$LEDGER" | grep -F -- "| to: $a |" | grep -E '^- [0-9-]+ archive ' | tail -1 | grep -o 'sha256: [0-9a-f]*' | sed 's/sha256: //')
      [ -n "$lsha" ] && [ "$lsha" = "$(sha "$STORE/$a")" ] || fail "archived file differs from original and from its ledger checksum: $a"
    fi
  done < <(archive_files "$STORE")
  # protected bullet + its indented block must survive in an ACTIVE or ARCHIVED file (evidence does not count)
  { tier_files "$STORE"; archive_files "$STORE"; } | while IFS= read -r p; do trim < "$STORE/$p"; done > "$protected_pool"
  while IFS= read -r p; do
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      grep -Fxq -- "$line" "$protected_pool" || fail "protected block line not in active/archive ($p): ${line:0:70}"
    done < <(nocr < "$BEFORE/$p" | awk '
      /^#+ / { match($0, /^#+/); lvl=RLENGTH; if (insec && lvl<=seclvl) insec=0 }
      /^#+ .*\[(NON-NEGOTIABLE|DIRECTIVE)[^]]*\]/ {insec=1; seclvl=lvl; print; next}
      insec {print; next}
      /^- .*\[(NON-NEGOTIABLE|DIRECTIVE)[^]]*\]/ {inblock=1; print; next}
      inblock && /^[ \t]+[^ \t]/ {print; next}
      {inblock=0}' | trim)
  done < <(tier_files "$BEFORE")
  # every original SPINE hook survives as a substring in SPINE, tier files, archived knowledge files or catalog
  # (never data/, evidence, or the ledger — the ledger holds every hook by construction)
  if [ -f "$BEFORE/SPINE.md" ]; then
    scope=(); [ -f "$STORE/SPINE.md" ] && scope+=("$STORE/SPINE.md"); [ -f "$STORE/CATALOG.md" ] && scope+=("$STORE/CATALOG.md")
    while IFS= read -r p; do scope+=("$STORE/$p"); done < <({ tier_files "$STORE"; archive_files "$STORE"; })
    while IFS= read -r line; do
      hook=$(hook_of_entry "$line")
      [ -n "$hook" ] || continue
      grep -Fq -- "$hook" "${scope[@]}" || fail "SPINE hook lost: ${hook:0:70}"
    done < <(nocr < "$BEFORE/SPINE.md" | grep '^- \[')
  fi
  rm -f "$cand" "$protected_pool"
  report C4
fi

exit $RC
