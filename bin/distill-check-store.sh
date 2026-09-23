#!/usr/bin/env bash
# aura-distill-check-store invariants v1
#
# distill-check-store.sh — deterministic invariants for a files-only aura-distill store
# (docs/design-files-only-memory.md, section 5). The one implementation of these checks:
# CI runs it against tests/files-only/, and the installers copy it to
# {DISTILL_DIR}/bin/ as an OPTIONAL helper the distiller runs when bash is available
# (distill-process.md "Self-check"). Nothing at runtime requires it; without bash the
# distiller follows the same invariants as a checklist. Line 2 is the version marker the
# runtime matches before it trusts this file; bump it when an invariant changes.
#
# Usage: distill-check-store.sh <store-dir> [--before <original-store-dir>]
#        distill-check-store.sh --print-catalog <store-dir>   CATALOG.md as it should be now (D4), on stdout
#        distill-check-store.sh --hashes <file>               "sha256 <raw>" and "sha256-norm <norm>" lines
#
# Read-only: never writes to either directory (the distiller writes what --print-catalog prints). Prints one "C<n> PASS|FAIL" line per check
# group (with indented reasons, and indented "note:" lines for tolerated drift) and exits
# 0 only when every group passes. Offline, no network, GNU and BSD toolchains. Line
# comparisons and line counts ignore carriage returns; checksums and byte counts are over
# raw bytes (byte identity means bytes), except that an archived file whose only change is
# its recall_count: frontmatter line (bumped by 1.1 clients) matches the ledger's
# sha256-norm: field and is reported as drift, not modification.
# Caps come from the environment:
#   SPINE_MAX_LINES (80) SPINE_MAX_BYTES (16000) ENTRY_MAX_BYTES (400)
#   FILE_MAX_LINES (60)  FILE_MAX_BYTES (6000)
#
# C1 SPINE budgets (an entry = its "- [" line plus any wrapped continuation lines); a
#    catalog entry line
# C2 pointers; catalog equals tree (presence, validated date, pinned, evidence counts,
#    archived rows' from/hook); evidence_for (an active, archived or adopted-legacy file); collisions; ledger syntax (known event words
#    only, events appended in non-decreasing date order), last-event agreement + sha256;
#    catalog staleness (full timestamps when both sides carry them); path containment
#    (D10) of SPINE, catalog and ledger paths; local/SPINE.md points only inside local/;
#    no symlinks; no legacy archive left inside a tier directory
# C3 tier-2 budgets, read_with (inline list, contained targets, no local/), split_from, oversize
# C4 (--before only) multiset line conservation over principle file + evidence twin
#    combined, protected blocks and retrieval-marker lines (never only in evidence),
#    archive identity, legacy identity (incl. adopted nested archives and unledgered
#    archive/<tier>/ files), pins, SPINE-hook survival; protected = bullet+block or
#    heading section carrying [NON-NEGOTIABLE…] or [DIRECTIVE…]; marker = the same shapes
#    carrying any Step 1d marker ([UPDATED…] [DEPRECATED…] [CORRECTED…] [IMPORTANT…]
#    [CONTEXT…] [PROVISIONAL…])
set -u
export LC_ALL=C

SPINE_MAX_LINES=${SPINE_MAX_LINES:-80}
SPINE_MAX_BYTES=${SPINE_MAX_BYTES:-16000}
ENTRY_MAX_BYTES=${ENTRY_MAX_BYTES:-400}
FILE_MAX_LINES=${FILE_MAX_LINES:-60}
FILE_MAX_BYTES=${FILE_MAX_BYTES:-6000}
TIERS="craft ops profile projects feedback"

STORE=""; BEFORE=""; MODE=check; HASH_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --before) BEFORE="$2"; shift 2 ;;
    --print-catalog) MODE=catalog; shift ;;
    --hashes) MODE=hashes; HASH_FILE="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    *) STORE="$1"; shift ;;
  esac
done
if [ "$MODE" = hashes ]; then [ -f "$HASH_FILE" ] || { echo "usage: $0 --hashes <file>" >&2; exit 2; }; STORE=.; fi
[ -n "$STORE" ] && [ -d "$STORE" ] || { echo "usage: $0 <store-dir> [--before <dir>] | --print-catalog <store-dir> | --hashes <file>" >&2; exit 2; }
# physical paths: a store reached through a symlinked home directory is not itself a symlink finding
STORE=$(cd "$STORE" && pwd -P)
if [ -n "$BEFORE" ]; then
  [ -d "$BEFORE" ] || { echo "no such dir: $BEFORE" >&2; exit 2; }
  BEFORE=$(cd "$BEFORE" && pwd -P)
fi

RC=0
FAILS=(); NOTES=()
fail() { FAILS+=("$1"); }
note() { NOTES+=("$1"); }
report() {
  if [ ${#FAILS[@]} -eq 0 ]; then echo "$1 PASS"; else
    echo "$1 FAIL"; for f in "${FAILS[@]}"; do echo "    - $f"; done; RC=1; fi
  [ ${#NOTES[@]} -eq 0 ] || for n in "${NOTES[@]}"; do echo "    note: $n"; done
  FAILS=(); NOTES=()
}
nocr() { tr -d '\r'; }
trim() { nocr | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }
sha_in() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
sha() { sha_in < "$1"; }
# sha_norm <file>: checksum with the frontmatter recall_count: line removed (the field 1.1
# clients bump on every archive read); bytes are otherwise untouched
sha_norm() { awk 'NR==1 && /^---\r?$/ {fm=1; print; next} fm && /^---\r?$/ {fm=0; print; next} fm && /^recall_count:/ {next} {print}' "$1" | sha_in; }
# same_or_drift <file-a> <file-b>: 0 = byte-identical, 1 = differ only in recall_count, 2 = differ
same_or_drift() { [ "$(sha "$1")" = "$(sha "$2")" ] && return 0; [ "$(sha_norm "$1")" = "$(sha_norm "$2")" ] && return 1; return 2; }
count_lines() { nocr < "$1" | grep -c '' ; }
count_bytes() { wc -c < "$1" | tr -d ' '; }
tier_files() { # $1 = root  → relative paths (a nested <tier>/**/archive/** file is a legacy archive, not a tier file)
  for t in $TIERS; do [ -d "$1/$t" ] && find "$1/$t" -type f -name '*.md'; done | sed "s|^$1/||" | grep -v '/archive/' | sort
}
nested_archives() { for t in $TIERS; do [ -d "$1/$t" ] && find "$1/$t" -type f -name '*.md'; done | sed "s|^$1/||" | grep '/archive/' | sort; return 0; }
archive_files() { [ -d "$1/archive" ] && find "$1/archive" -type f -name '*.md' ! -name 'LEDGER.md' | sed "s|^$1/||" | sort; return 0; }
evidence_files() { [ -d "$1/evidence" ] && find "$1/evidence" -type f -name '*.md' | sed "s|^$1/||" | sort; return 0; }
frontmatter_less() { nocr < "$1" | awk 'NR==1 && $0=="---"{fm=1; next} fm && $0=="---"{fm=0; next} !fm' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }   # trimmed body lines
frontmatter() { nocr < "$1" | awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}'; }
fm_value() { frontmatter "$1" | grep "^$2:" | head -1 | sed "s/^$2:[[:space:]]*//"; }
newest_stamp() { nocr < "$1" | grep -oE 'last_(validated|updated): *[0-9]{4}-[0-9]{2}-[0-9]{2}' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | tail -1; }
catalog_row() { grep -F -- "- $2 |" "$1" | head -1 | nocr; }
is_legacy() { case "${1#archive/}" in legacy/*) return 0 ;; */*) return 1 ;; *) return 0 ;; esac; }   # structural: flat under archive/ or under archive/legacy/ = legacy
# contained <path> <kind>: D10. Relative, no "." or ".." segment, not absolute, no "~", no
# backslash or drive colon, and inside the allowed roots. kind: tier (a tier directory),
# archived (archive/<tier>/...), store (tier, archive/ or evidence/), spine (tier or CATALOG.md),
# local (inside local/: the only place a pointer in the machine-local local/SPINE.md may lead)
contained() {
  local p="$1" first
  case "$p" in ''|/*|\~*|*\\*|*:*) return 1 ;; esac
  case "/$p/" in */../*|*/./*|*//*) return 1 ;; esac
  first=${p%%/*}
  case "$2" in
    tier) [ "$first" != "$p" ] && case " $TIERS " in *" $first "*) return 0 ;; esac; return 1 ;;
    archived) case "$p" in archive/*) contained "${p#archive/}" tier ;; *) return 1 ;; esac ;;
    spine) [ "$p" = "CATALOG.md" ] && return 0; contained "$p" tier ;;
    local) [ "$first" = local ] && [ "$first" != "$p" ] ;;
    store) case "$first" in archive|evidence) [ "$first" != "$p" ] ;; *) contained "$p" tier ;; esac ;;
  esac
}
EVENT_RE='^- [0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}(:[0-9]{2})?Z)? '
stamp_newer() { # stamp_newer A B: A later than B; full timestamps compared only when BOTH carry a time
  case "$1$2" in *T*T*) [ "$1" \> "$2" ] ;; *) [ "${1:0:10}" \> "${2:0:10}" ] ;; esac
}
# segments <line>: a ledger or catalog line split on " | " from the left. A literal "|" inside a
# free-text field (hook, reason, scope) is written "\|" (D3/D4), so " \| " never splits.
segments() { printf '%s\n' "$1" | awk '{ n = split($0, a, / \| /); for (i = 1; i <= n; i++) print a[i] }'; }
# field <line> <name>: the value of the FIRST segment that starts with "<name>: "
field() { segments "$1" | awk -v k="$2: " 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }' | sed 's/[[:space:]]*$//'; }
# ledger_last_events: "<path> <archive|restore>" for the newest event per path
# (a top-level function: bash 3.2 cannot parse a case statement inside a process substitution)
ledger_last_events() {
  nocr < "$LEDGER" | grep -E "$EVENT_RE"'(archive|restore) ' | while IFS= read -r l; do
    e=$(printf '%s' "$l" | awk '{print $3}'); to=$(field "$l" to)
    if [ "$e" = "archive" ]; then printf '%s %s\n' "${to#archive/}" archive
    elif [ "$e" = "restore" ]; then printf '%s %s\n' "$to" restore; fi
  done | awk '{last[$1]=$2} END{for (k in last) print k, last[k]}'
}
# spine_entries <file>: one line per entry, its wrapped continuation lines (any following
# line that is not blank, a heading, a comment or another "- " item) joined with one space,
# so the per-entry byte cap covers the whole entry (one joining byte stands in for each newline)
spine_entries() {
  nocr < "$1" | awk '
    function flush() { if (e != "") print e; e = "" }
    /^- \[/ { flush(); e = $0; next }
    /^[ \t]*$/ || /^#/ || /^- / || /^<!--/ { flush(); next }
    { if (e != "") { sub(/^[ \t]+/, ""); e = e " " $0 } }
    END { flush() }'
}
# spine_hook_lines <file>: the hook of each entry's first line, then each continuation line on its own
spine_hook_lines() {
  nocr < "$1" | awk '
    /^- \[/ { inentry = 1; print "E\t" $0; next }
    /^[ \t]*$/ || /^#/ || /^- / || /^<!--/ { inentry = 0; next }
    inentry { sub(/^[ \t]+/, ""); print "C\t" $0 }'
}
hook_of_entry() { printf '%s' "$1" | sed -E 's/^- \[[^]]*\]\([^)]*\)( *\+ *\[[^]]*\]\([^)]*\))*//' | sed 's/^ *— *//; s/^ *-- *//'; }

# ── modes that print instead of checking ─────────────────────────────────────
if [ "$MODE" = hashes ]; then
  printf 'sha256 %s\nsha256-norm %s\n' "$(sha "$HASH_FILE")" "$(sha_norm "$HASH_FILE")"; exit 0
fi
if [ "$MODE" = catalog ]; then
  # D4: every field derived from the tree and the ledger; a literal "|" in free text is "\|"
  esc() { sed 's/\\|/\x01/g; s/|/\\|/g; s/\x01/\\|/g'; }
  scope_of() { local sc; sc=$(fm_value "$1" scope); [ -n "$sc" ] || sc=$(nocr < "$1" | grep -m1 '^#' | sed 's/^#* *//'); [ -n "$sc" ] || sc="(no scope)"; printf '%s' "$sc" | esc; }
  LEDGER="$STORE/archive/LEDGER.md"
  printf '# Knowledge catalog\n\n<!-- Complete inventory, rebuilt by /distill. Not loaded at session start. rebuilt: %s -->\n\n## active\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  while IFS= read -r p; do
    f="$STORE/$p"; row="- $p | $(scope_of "$f")"
    stamp=$(newest_stamp "$f"); [ -n "$stamp" ] && row="$row | validated $stamp"
    [ "$(fm_value "$f" lifecycle)" = pinned ] && row="$row | pinned"
    ov=$(fm_value "$f" oversize); [ -n "$ov" ] && row="$row | oversize: $(printf '%s' "$ov" | esc)"
    printf '%s\n' "$row"
  done < <(tier_files "$STORE")
  printf '\n## archived\n'
  while IFS= read -r a; do
    f="$STORE/$a"; row="- $a | $(scope_of "$f")"
    if is_legacy "$a"; then row="$row | legacy"
    elif [ -f "$LEDGER" ]; then
      ev=$(nocr < "$LEDGER" | grep -F -- "| to: $a |" | grep -E "$EVENT_RE"'archive ' | tail -1)
      if [ -n "$ev" ]; then
        d=$(printf '%s' "$ev" | awk '{print $2}'); row="$row | archived ${d:0:10}"
        r=$(field "$ev" reason); [ -n "$r" ] && row="$row | reason: $r"
        row="$row | from $(field "$ev" from) | hook: $(hook_of_entry "$(field "$ev" spine-entry)" | sed 's/[[:space:]]*$//')"
      fi
    fi
    printf '%s\n' "$row"
  done < <(archive_files "$STORE")
  printf '\n## evidence\n'
  while IFS= read -r e; do
    printf -- '- %s | for %s | %s entries\n' "$e" "$(fm_value "$STORE/$e" evidence_for | esc)" "$(nocr < "$STORE/$e" | grep -c '^- ')"
  done < <(evidence_files "$STORE")
  exit 0
fi

# ── C1: SPINE budgets ────────────────────────────────────────────────────────
SPINE="$STORE/SPINE.md"
if [ ! -f "$SPINE" ]; then fail "SPINE.md missing"; else
  lines=$(count_lines "$SPINE"); bytes=$(count_bytes "$SPINE")
  [ "$lines" -le "$SPINE_MAX_LINES" ] || fail "SPINE has $lines lines (max $SPINE_MAX_LINES)"
  [ "$bytes" -le "$SPINE_MAX_BYTES" ] || fail "SPINE is $bytes bytes (max $SPINE_MAX_BYTES)"
  while IFS= read -r line; do
    n=${#line}
    [ "$n" -le "$ENTRY_MAX_BYTES" ] || fail "entry over $ENTRY_MAX_BYTES bytes ($n): ${line:0:60}..."
  done < <(spine_entries "$SPINE")
  nocr < "$SPINE" | grep -q '^- \[[^]]*\](CATALOG.md)' || fail "SPINE has no catalog line"
fi
report C1

# ── C2: pointers, catalog equals tree, evidence_for, collisions, ledger ──────
if [ -f "$SPINE" ]; then
  while IFS= read -r p; do
    contained "$p" spine || { fail "uncontained path in SPINE.md: $p"; continue; }
    [ -f "$STORE/$p" ] || fail "SPINE pointer to missing file: $p"
  done \
    < <(nocr < "$SPINE" | grep '^- \[' | grep -o '](\([^)]*\.md\))' | sed 's/^](//;s/)$//' | sort -u)
  # pointers come only from entry lines ("- [" ...), never from comments or prose
  spine_ptrs=$(nocr < "$SPINE" | grep '^- \[' | grep -o '](\([^)]*\.md\))' | sed 's/^](//;s/)$//' | sort -u)
  while IFS= read -r p; do printf '%s\n' "$spine_ptrs" | grep -Fxq -- "$p" || fail "active file has no SPINE pointer: $p"; done < <(tier_files "$STORE")
fi
# the machine-local overlay: its SPINE may point only inside local/ (D10), and the targets exist
LOCAL_SPINE="$STORE/local/SPINE.md"
if [ -f "$LOCAL_SPINE" ]; then
  while IFS= read -r p; do
    contained "$p" local || { fail "local/SPINE.md may point only inside local/: $p"; continue; }
    [ -f "$STORE/$p" ] || fail "local/SPINE.md pointer to missing file: $p"
  done < <(nocr < "$LOCAL_SPINE" | grep '^- \[' | grep -o '](\([^)]*\.md\))' | sed 's/^](//;s/)$//' | sort -u)
fi
CAT="$STORE/CATALOG.md"
LEDGER="$STORE/archive/LEDGER.md"
if [ ! -f "$CAT" ]; then fail "CATALOG.md missing"; else
  while IFS= read -r p; do grep -Fq -- "- $p |" "$CAT" || fail "file not in catalog: $p"; done \
    < <({ tier_files "$STORE"; archive_files "$STORE"; evidence_files "$STORE"; } | sort)
  while IFS= read -r p; do
    contained "$p" store || { fail "uncontained path in CATALOG.md: $p"; continue; }
    [ -f "$STORE/$p" ] || fail "catalog line points at missing file: $p"
  done \
    < <(nocr < "$CAT" | grep -o '^- [^|]* |' | sed 's/^- //;s/ |$//')
  # row syntax: path | free-text scope | then only known fields (a literal "|" in free text is "\|")
  while IFS= read -r row; do
    bad_seg=$(segments "$row" | sed 1,2d | grep -vE '^(validated |archived |reason: |from |hook: |pinned$|legacy$|oversize(: |$)|[0-9]+ entries$)' | head -1)
    [ -n "$bad_seg" ] && fail "unescaped ' | ' inside a free-text field of CATALOG.md (write it as '\|'): ${bad_seg:0:60}"
  done < <(nocr < "$CAT" | grep '^- ')
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
    elif [ ! -f "$STORE/$target" ] && [ ! -f "$STORE/archive/$target" ]; then
      # a 1.1 client archived the file without a ledger line and migrate-store adopted it (D3):
      # the twin belongs to the adopted legacy file
      if [ -f "$STORE/archive/legacy/archive/$target" ]; then note "evidence twin of an adopted legacy archive: $e (archive/legacy/archive/$target)"
      else fail "orphan evidence: $e (evidence_for $target is neither active nor archived)"; fi
    fi
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
    ev=$(nocr < "$LEDGER" | grep -F -- "| to: $a |" | grep -E "$EVENT_RE"'archive ' | tail -1)
    if [ -z "$ev" ]; then fail "no ledger archive event for: $a (unledgered: pending adoption by migrate-store)"; continue; fi
    lsha=$(field "$ev" sha256); lnorm=$(field "$ev" sha256-norm)
    if [ "$lsha" != "$(sha "$STORE/$a")" ]; then
      # a 1.1 client bumps recall_count: on every archive read; the normalised checksum
      # (that frontmatter line removed) tells drift from modification (design section 4)
      if [ -n "$lnorm" ] && [ "$lnorm" = "$(sha_norm "$STORE/$a")" ]; then note "recall_count drift only (tolerated): $a"
      else fail "ledger sha256 does not match archived file: $a"; fi
    fi
    lhook=$(hook_of_entry "$(field "$ev" spine-entry)" | sed 's/[[:space:]]*$//')
    chook=$(field "$row" hook)
    [ "$lhook" = "$chook" ] || fail "catalog hook differs from ledger spine-entry hook: $a"
  done < <(archive_files "$STORE")
fi
# ledger syntax: every "- " line is a known event with contained, mutually consistent paths.
# Unknown event words fail loudly instead of being skipped. "The newest event decides" means
# the LAST line in the file, so lines must be appended in non-decreasing date order: a merge
# of two machines' copies (#61) interleaves by timestamp, and an out-of-order line fails here
# instead of silently changing which event is last.
if [ -f "$LEDGER" ]; then
  prev_stamp=""
  while IFS= read -r l; do
    if ! printf '%s\n' "$l" | grep -Eq "$EVENT_RE"; then fail "malformed ledger line (no leading date): ${l:0:70}"; continue; fi
    stamp=$(printf '%s' "$l" | awk '{print $2}')
    if [ -n "$prev_stamp" ] && stamp_newer "$prev_stamp" "$stamp"; then fail "ledger events out of order: $stamp appended after $prev_stamp (append order must be date order)"; fi
    prev_stamp=$stamp
    ev=$(printf '%s' "$l" | sed -E "s/$EVENT_RE//; s/ *\|.*//")
    case "$ev" in
      archive|restore|"restore (modified)") ;;
      *) fail "unknown ledger event '$ev': ${l:0:70}"; continue ;;
    esac
    # each segment after the event is a known key, and no key repeats (a forged "| to: ..." inside a hook repeats "to")
    bad_seg=$(segments "$l" | sed 1d | grep -vE '^(from|to|sha256|sha256-norm|reason|spine-entry): ' | head -1)
    [ -z "$bad_seg" ] && bad_seg=$(segments "$l" | sed 1d | sed 's/: .*//' | sort | uniq -d | head -1)
    if [ -n "$bad_seg" ]; then fail "unescaped ' | ' inside a free-text field of archive/LEDGER.md (write it as '\|'): ${bad_seg:0:60}"; continue; fi
    fr=$(field "$l" from); to=$(field "$l" to)
    contained "$fr" store || { fail "uncontained path in archive/LEDGER.md from: $fr"; continue; }
    contained "$to" store || { fail "uncontained path in archive/LEDGER.md to: $to"; continue; }
    if [ "$ev" = archive ]; then
      { contained "$fr" tier && [ "$to" = "archive/$fr" ]; } || fail "ledger archive line must move X to archive/X: from $fr to $to"
    else
      { contained "$to" tier && [ "$fr" = "archive/$to" ]; } || fail "ledger restore line must move archive/X to X: from $fr to $to"
    fi
  done < <(nocr < "$LEDGER" | grep '^- ')
fi
# ledger last event per path must agree with the tree
if [ -f "$LEDGER" ]; then
  while read -r x ev; do
    case "$ev" in
      archive) { [ -f "$STORE/archive/$x" ] && [ ! -f "$STORE/$x" ]; } || fail "ledger says archived but tree disagrees: $x" ;;
      restore) { [ -f "$STORE/$x" ] && [ ! -f "$STORE/archive/$x" ]; } || fail "ledger says restored but tree disagrees: $x" ;;
    esac
  done < <(ledger_last_events | while read -r x ev; do contained "$x" tier && printf '%s %s\n' "$x" "$ev"; done | sort)
fi
# catalog rebuilt stamp must not predate the newest ledger event
if [ -f "$LEDGER" ] && [ -f "$CAT" ]; then
  # full UTC timestamps (2026-09-11T10:00:00Z) are compared when both sides carry one; a
  # date-only side is compared by date, which cannot see a same-day move after the rebuild
  rebuilt=$(nocr < "$CAT" | grep -oE 'rebuilt: [0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}(:[0-9]{2})?Z)?' | head -1 | sed 's/rebuilt: //')
  newest=$(nocr < "$LEDGER" | grep -oE '^- [0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}(:[0-9]{2})?Z)?' | sed 's/^- //' | sort | tail -1)
  if [ -z "$rebuilt" ]; then fail "catalog has no rebuilt: stamp"
  elif [ -n "$newest" ] && stamp_newer "$newest" "$rebuilt"; then fail "catalog stale: rebuilt $rebuilt but newest ledger event is $newest"; fi
fi
# collisions: a path may not be both active and archived
while IFS= read -r p; do [ -f "$STORE/archive/$p" ] && fail "path exists both active and archived: $p"; done < <(tier_files "$STORE")
# a legacy archive left inside a tier directory must be adopted by migration (D3)
while IFS= read -r p; do fail "legacy archive inside a tier directory: $p (migration adopts it to archive/legacy/$p)"; done < <(nested_archives "$STORE")
# every path must resolve inside the store: no symlinks (D10)
while IFS= read -r l; do fail "symlink in store: ${l#$STORE/}"; done \
  < <(for d in $TIERS archive evidence local SPINE.md CATALOG.md; do [ -e "$STORE/$d" ] || [ -L "$STORE/$d" ] && find "$STORE/$d" -type l; done)
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
          contained "$t" store || { fail "uncontained path in $p read_with: $t"; continue; }
          [ -f "$STORE/$t" ] || fail "$p read_with target missing: $t"
        done < <(printf '%s\n' "$rw" | tr ',' '\n' | trim) ;;
      *) fail "$p read_with must be an inline list [a.md, b.md]" ;;
    esac
  fi
  sf=$(fm_value "$f" split_from)
  if [ -n "$sf" ]; then
    if ! contained "$sf" tier; then fail "uncontained path in $p split_from: $sf"
    elif [ ! -f "$STORE/$sf" ]; then fail "$p split_from target missing: $sf"; fi
  fi
done < <(tier_files "$STORE")
report C3

# ── C4: lossless migration (only with --before) ──────────────────────────────
if [ -n "$BEFORE" ]; then
  cand=$(mktemp); protected_pool=$(mktemp)
  # same_file <after> <before>: byte-identical, or identical but for a bumped recall_count (noted)
  same_file() { same_or_drift "$1" "$2"; case $? in 0) return 0 ;; 1) note "recall_count drift only (tolerated): ${1#$STORE/}"; return 0 ;; esac; return 1; }
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
    # multiset conservation over the COMBINED pool: principle file + its pre-existing evidence
    # twin before, against every candidate after. A line present in both before (a duplicate)
    # must survive twice; an append that skipped it as "already present" fails here.
    while read -r k line; do
      [ -z "$line" ] && continue
      have=$(grep -Fxc -- "$line" "$cand")
      [ "$have" -ge "$k" ] || fail "line lost from $p (before x$k, after x$have): ${line:0:70}"
    done < <({ trim < "$BEFORE/$p"; [ -f "$BEFORE/evidence/$p" ] && frontmatter_less "$BEFORE/evidence/$p"; } | grep -v '^$' | sort | uniq -c | sed 's/^ *//')
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
  # every archive file with no ledger archive event at migration time (the real-store shape:
  # archive/<tier>/x.md from the old compaction, no ledger) is adopted byte-identically at archive/legacy/<path>
  BLEDGER="$BEFORE/archive/LEDGER.md"
  while IFS= read -r a; do
    is_legacy "$a" && continue
    [ -f "$BLEDGER" ] && nocr < "$BLEDGER" | grep -F -- "| to: $a |" | grep -Eq "$EVENT_RE"'archive ' && continue
    if [ ! -f "$STORE/archive/legacy/$a" ]; then fail "unledgered archive not adopted: $a (expected archive/legacy/$a)"
    elif ! same_file "$STORE/archive/legacy/$a" "$BEFORE/$a"; then fail "legacy archive file changed: archive/legacy/$a"; fi
  done < <(archive_files "$BEFORE")
  # nothing leaves the archive: every pre-existing archive file still exists (or was adopted)
  while IFS= read -r a; do [ -f "$STORE/$a" ] || [ -f "$STORE/archive/legacy/$a" ] || fail "archive file deleted: $a"; done < <(archive_files "$BEFORE")
  # legacy archives nested inside a tier directory before are adopted byte-identically at archive/legacy/<path>
  while IFS= read -r n; do
    if [ ! -f "$STORE/archive/legacy/$n" ]; then fail "nested legacy archive not adopted: $n (expected archive/legacy/$n)"
    elif ! same_file "$STORE/archive/legacy/$n" "$BEFORE/$n"; then fail "legacy archive file changed: archive/legacy/$n"; fi
  done < <(nested_archives "$BEFORE")
  # archived files. Legacy: byte-identical to its own before copy (same path, or the nested path it was
  # adopted from). Non-legacy: byte-identical to the before copy at the same archive path (already
  # archived; --before may itself be a migrated store) or to the original tier file (moved in this run),
  # or else equal to its last ledger archive checksum (edited after migration and before a later move,
  # or restored, edited and re-archived; its original lines are covered by conservation). A split
  # child created by this run and archived with its family has no original of its own; its parent must.
  while IFS= read -r a; do
    rel=${a#archive/}; h=$(sha "$STORE/$a")
    if is_legacy "$a"; then
      if [ -f "$BEFORE/$a" ]; then same_file "$STORE/$a" "$BEFORE/$a" || fail "legacy archive file changed: $a"
      elif [ -f "$BEFORE/${a#archive/legacy/}" ] && [ "$a" != "${a#archive/legacy/}" ]; then :   # adoption, checked above
      else fail "archived file has no original: $a"; fi
      continue
    fi
    [ -f "$BEFORE/$a" ] && same_file "$STORE/$a" "$BEFORE/$a" && continue
    [ -f "$BEFORE/$rel" ] && same_file "$STORE/$a" "$BEFORE/$rel" && continue
    parent=$(fm_value "$STORE/$a" split_from)
    if [ ! -f "$BEFORE/$a" ] && [ ! -f "$BEFORE/$rel" ] && \
       ! { [ -n "$parent" ] && contained "$parent" tier && { [ -f "$BEFORE/$parent" ] || [ -f "$BEFORE/archive/$parent" ]; }; }; then
      fail "archived file has no original: $a"; continue
    fi
    lev=$([ -f "$LEDGER" ] && nocr < "$LEDGER" | grep -F -- "| to: $a |" | grep -E "$EVENT_RE"'archive ' | tail -1)
    lsha=$(field "$lev" sha256); lnorm=$(field "$lev" sha256-norm)
    { [ -n "$lsha" ] && [ "$lsha" = "$h" ]; } || { [ -n "$lnorm" ] && [ "$lnorm" = "$(sha_norm "$STORE/$a")" ]; } \
      || fail "archived file differs from original and from its ledger checksum: $a"
  done < <(archive_files "$STORE")
  # protected bullet + its indented block, and every line carrying a retrieval marker, must survive in an
  # ACTIVE or ARCHIVED file (evidence does not count: retrieval never reads it, and the markers steer retrieval)
  { tier_files "$STORE"; archive_files "$STORE"; } | while IFS= read -r p; do trim < "$STORE/$p"; done > "$protected_pool"
  while IFS= read -r p; do
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      grep -Fxq -- "$line" "$protected_pool" || fail "protected block line not in active/archive ($p): ${line:0:70}"
    done < <(nocr < "$BEFORE/$p" | awk -v M='\\[(NON-NEGOTIABLE|DIRECTIVE|UPDATED|DEPRECATED|CORRECTED|IMPORTANT|CONTEXT|PROVISIONAL)[^]]*\\]' '
      /^#+ / { match($0, /^#+/); lvl=RLENGTH; if (insec && lvl<=seclvl) insec=0 }
      /^#+ / && $0 ~ M {insec=1; seclvl=lvl; print; next}
      insec {print; next}
      /^- / && $0 ~ M {inblock=1; print; next}
      inblock && /^[ \t]+[^ \t]/ {print; next}
      {inblock=0}
      $0 ~ M {print}' | trim)
  done < <(tier_files "$BEFORE")
  # every original SPINE hook survives as a substring in SPINE, tier files, archived knowledge files or catalog
  # (never data/, evidence, or the ledger — the ledger holds every hook by construction)
  if [ -f "$BEFORE/SPINE.md" ]; then
    scope=(); [ -f "$STORE/SPINE.md" ] && scope+=("$STORE/SPINE.md"); [ -f "$STORE/CATALOG.md" ] && { sed 's/\\|/|/g' "$STORE/CATALOG.md" > "$cand"; scope+=("$cand"); }   # catalog unescaped (D4)
    while IFS= read -r p; do scope+=("$STORE/$p"); done < <({ tier_files "$STORE"; archive_files "$STORE"; })
    # a wrapped entry's continuation lines are hook text too; each must survive
    while IFS="$(printf '\t')" read -r kind line; do
      if [ "$kind" = E ]; then hook=$(hook_of_entry "$line"); else hook=$line; fi
      hook=$(printf '%s' "$hook" | sed 's/[[:space:]]*$//')
      [ -n "$hook" ] || continue
      grep -Fq -- "$hook" "${scope[@]}" || fail "SPINE hook lost: ${hook:0:70}"
    done < <(spine_hook_lines "$BEFORE/SPINE.md")
  fi
  rm -f "$cand" "$protected_pool"
  report C4
fi

exit $RC
