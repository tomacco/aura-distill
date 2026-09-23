#!/usr/bin/env bash
# run-files-only-tests.sh — regression suite for the files-only memory redesign (#75).
#
# 1. store-before MUST fail C1, C2 and C3: the diagnosis (fat index, no catalog,
#    evidence inflating a tier file) reproduced on a synthetic store.
# 2. store-after --before store-before MUST pass everything: the redesign fixes the
#    diagnosis without losing a line, a checksum, a protected block, a hook or a pin.
# 3. Every tamper case MUST be caught, each with a non-zero exit and its named reason;
#    every fail branch of bin/distill-check-store.sh has at least one dedicated case. The
#    positive cases (oversize: exemption, two restores, merged-line pointer removal, a
#    preserved pre-existing duplicate, a timestamped catalog, a re-archive after an edit, an
#    adopted nested legacy archive, escaped pipes, repeated adoption, recall_count drift)
#    MUST pass.
# The checker under test is the shipped file (bin/distill-check-store.sh, the same bytes the
# installers copy to {DISTILL_DIR}/bin/), never a copy.
set -u
cd "$(dirname "$0")"
CHECK=../../bin/distill-check-store.sh
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
# tamper <name> <expected-substring> <shell-commands run with $s = a copy of store-after>
tamper() {
  local name="$1" expect="$2" cmds="$3" tmp out rc
  tmp=$(mktemp -d); cp -r store-after "$tmp/s"; s="$tmp/s"
  ( s="$s"; eval "$cmds" )
  out=$(bash "$CHECK" "$s" --before store-before 2>&1); rc=$?
  if [ $rc -ne 0 ] && echo "$out" | grep -Fq -- "$expect"; then ok "$name"; else bad "$name (rc=$rc)"; echo "$out" | sed 's/^/       /'; fi
  rm -rf "$tmp"
}
# expect_pass <name> <shell-commands>: the modified copy must still pass every check
expect_pass() {
  local name="$1" cmds="$2" tmp out rc
  tmp=$(mktemp -d); cp -r store-after "$tmp/s"; s="$tmp/s"
  ( s="$s"; eval "$cmds" )
  out=$(bash "$CHECK" "$s" --before store-before 2>&1); rc=$?
  if [ $rc -eq 0 ]; then ok "$name"; else bad "$name (rc=$rc)"; echo "$out" | sed 's/^/       /'; fi
  rm -rf "$tmp"
}

shaf() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d" " -f1; else shasum -a 256 "$1" | cut -d" " -f1; fi; }
# with_before <name> <expected-substring|PASS> <before-base> <commands on $b> <commands on $s>:
# $b is a copy of <before-base>, $s a copy of store-after; checks $s --before $b
with_before() {
  local name="$1" expect="$2" base="$3" bcmds="$4" cmds="$5" tmp out rc
  tmp=$(mktemp -d); cp -r "$base" "$tmp/b"; cp -r store-after "$tmp/s"
  ( b="$tmp/b"; eval "$bcmds" ); ( s="$tmp/s"; eval "$cmds" )
  out=$(bash "$CHECK" "$tmp/s" --before "$tmp/b" 2>&1); rc=$?
  if [ "$expect" = PASS ]; then
    if [ $rc -eq 0 ]; then ok "$name"; else bad "$name (rc=$rc)"; echo "$out" | sed 's/^/       /'; fi
  elif [ $rc -ne 0 ] && echo "$out" | grep -Fq -- "$expect"; then ok "$name"
  else bad "$name (rc=$rc)"; echo "$out" | sed 's/^/       /'; fi
  rm -rf "$tmp"
}

echo "== store-before (expect C1, C2, C3 to fail) =="
out=$(bash "$CHECK" store-before 2>&1); rc=$?
echo "$out" | sed 's/^/     /'
[ $rc -ne 0 ] && ok "before store is rejected" || bad "before store was accepted"
for c in C1 C2 C3; do
  echo "$out" | grep -q "^$c FAIL" && ok "$c fails on before" || bad "$c did not fail on before"
done
for r in "entry over 400 bytes (603)" "SPINE has no catalog line" "CATALOG.md missing" "craft/testing.md has 69 lines (max 60)"; do
  echo "$out" | grep -Fq -- "$r" && ok "before store diagnosis: $r" || bad "before store diagnosis missing: $r"
done

echo "== store-after --before store-before (expect all PASS) =="
out=$(bash "$CHECK" store-after --before store-before 2>&1); rc=$?
echo "$out" | sed 's/^/     /'
[ $rc -eq 0 ] && ok "after store passes" || bad "after store failed"
for c in C1 C2 C3 C4; do
  echo "$out" | grep -q "^$c PASS" && ok "$c passes on after" || bad "$c did not pass on after"
done

echo "== tamper cases (each must fail with the named reason) =="
tamper "modified archived file" "archived file differs from original" \
  'printf "\n" >> "$s/archive/projects/atlas.md"'
tamper "ledger checksum mismatch" "ledger sha256 does not match" \
  'h=$(grep -o "sha256: [0-9a-f]\{8\}" "$s/archive/LEDGER.md" | head -1 | sed "s/sha256: //");
   sed -i.bak "s/sha256: $h/sha256: 00000000/" "$s/archive/LEDGER.md"; rm -f "$s/archive/LEDGER.md.bak"'
tamper "ledger archive event for a file that is still active" "ledger says archived but tree disagrees: projects/beacon.md" \
  'printf -- "- 2026-09-12 archive | from: projects/beacon.md | to: archive/projects/beacon.md | sha256: 0 | reason: crash test | spine-entry: - [Beacon](projects/beacon.md) — Beacon.\n" >> "$s/archive/LEDGER.md"'
tamper "dropped protected line" "line lost from feedback/preferences.md" \
  'sed -i.bak "/NON-NEGOTIABLE 2026-05-02\] Never claim/d" "$s/feedback/preferences.md"; rm -f "$s/feedback/preferences.md.bak"'
tamper "protected block demoted to evidence only" "protected block line not in active/archive" \
  'mkdir -p "$s/evidence/projects"; grep "NON-NEGOTIABLE\] Invoice records" "$s/projects/comet.md" > "$s/e.tmp";
   sed -i.bak "/NON-NEGOTIABLE\] Invoice records/d" "$s/projects/comet.md"; rm -f "$s/projects/comet.md.bak";
   { printf -- "---\nevidence_for: projects/comet.md\n---\n"; cat "$s/e.tmp"; } > "$s/evidence/projects/comet.md"; rm -f "$s/e.tmp";
   printf -- "- evidence/projects/comet.md | for projects/comet.md | 1 entries\n" >> "$s/CATALOG.md"'
tamper "lost SPINE hook" "SPINE hook lost" \
  'sed -i.bak "/^## Index detail/,\$d" "$s/profile/noor.md"; rm -f "$s/profile/noor.md.bak"'
tamper "dropped one of two identical lines (multiset)" "line lost from craft/testing.md (before x2, after x1)" \
  'awk "/last_validated: 2026-08-12/ && !seen {seen=1; next} {print}" "$s/craft/testing-2.md" > "$s/t.tmp"; mv "$s/t.tmp" "$s/craft/testing-2.md"'
tamper "lost split child" "line lost from craft/testing.md" \
  'rm "$s/craft/testing-2.md"; sed -i.bak "s| + \[continued\](craft/testing-2.md)||" "$s/SPINE.md"; sed -i.bak "/craft\/testing-2.md/d" "$s/CATALOG.md"; rm -f "$s/SPINE.md.bak" "$s/CATALOG.md.bak"'
tamper "dangling read_with target" "read_with target missing: ops/missing.md" \
  'sed -i.bak "s|^read_with: \[ops/deploy.md\]|read_with: [ops/deploy.md, ops/missing.md]|" "$s/projects/beacon.md"; rm -f "$s/projects/beacon.md.bak"'
tamper "block-list read_with" "read_with must be an inline list" \
  'awk "{ if (\$0 ~ /^read_with: \\[ops\\/deploy.md\\]/) { print \"read_with:\"; print \"  - ops/deploy.md\" } else print }" "$s/projects/beacon.md" > "$s/b.tmp"; mv "$s/b.tmp" "$s/projects/beacon.md"'
tamper "orphan evidence file" "orphan evidence: evidence/craft/ghost.md" \
  'printf -- "---\nevidence_for: craft/ghost.md\n---\n- 2026-09-01 observe: nothing\n" > "$s/evidence/craft/ghost.md";
   printf -- "- evidence/craft/ghost.md | for craft/ghost.md | 1 entries\n" >> "$s/CATALOG.md"'
tamper "active/archived collision" "path exists both active and archived: projects/atlas.md" \
  'cp "$s/archive/projects/atlas.md" "$s/projects/atlas.md";
   printf -- "- [Atlas](projects/atlas.md) — Atlas migration. Read when working in atlas-* repos.\n" >> "$s/SPINE.md";
   printf -- "- projects/atlas.md | Atlas data-platform migration | validated 2026-04-02\n" >> "$s/CATALOG.md"'

echo "== exemption case (must pass) =="
expect_pass "oversize: exemption honoured for a 7 KB pinned file" \
  'sed -i.bak "s/^lifecycle: pinned$/lifecycle: pinned\noversize: legal wording stays in one file/" "$s/projects/comet.md"; rm -f "$s/projects/comet.md.bak";
   { printf -- "\n- [NON-NEGOTIABLE] "; head -c 7000 /dev/zero | tr "\\0" "x"; printf "\n"; } >> "$s/projects/comet.md"'

# restore_case <name> <event-text>: atlas comes back per D7 Restore (ledger line, move back,
# short entry rewritten within the cap, entire saved hook under "Index detail", catalog rebuilt)
restore_case() {
  expect_pass "$1" '
    ev="'"$2"'"
    printf -- "- 2026-09-12 %s | from: archive/projects/atlas.md | to: projects/atlas.md | sha256: 12c18385e88e5c0d0ebb9607f23ee8da4f5bb6fe96970f3f56a1ecf5fc84f98f | reason: user request\n" "$ev" >> "$s/archive/LEDGER.md";
    mv "$s/archive/projects/atlas.md" "$s/projects/atlas.md";
    hook=$(sed -n "s/.*| spine-entry: - \[Atlas\](projects\/atlas.md) — //p" "$s/archive/LEDGER.md" | head -1);
    printf -- "\n## Index detail (moved from SPINE 2026-09-12)\n\n%s\n" "$hook" >> "$s/projects/atlas.md";
    printf -- "- [Atlas](projects/atlas.md) — Atlas data-platform migration to the lakehouse; parquet, ingest_date partitions, schema registry directive; open items. Read when working in the atlas-* repos.\n" >> "$s/SPINE.md";
    sed -i.bak "/^- archive\/projects\/atlas.md |/d; s/^<!-- Complete inventory.*rebuilt: 2026-09-11 -->/<!-- Complete inventory, rebuilt by \/distill. Not loaded at session start. rebuilt: 2026-09-12 -->/" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak";
    printf -- "- projects/atlas.md | Atlas data-platform migration — legacy warehouse to lakehouse | validated 2026-04-02\n" >> "$s/CATALOG.md"'
}
echo "== restore cases (must pass: D7 restore obeys D1) =="
restore_case "restore: atlas back, short entry rewritten, entire saved hook under Index detail" "restore"
restore_case "restore (modified) event parses the same way" "restore (modified)"

echo "== tamper: catalog older than the newest ledger event =="
tamper "stale catalog rebuilt stamp" "catalog stale: rebuilt" \
  'sed -i.bak "s/rebuilt: 2026-09-11/rebuilt: 2026-01-01/" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'

echo "== tamper cases added for every checker branch the suite did not exercise =="
tamper "Index detail holds only the tail of the hook" "SPINE hook lost" \
  'sed -i.bak "s/^platform engineer at a fictional logistics company; owns the Atlas, Beacon and Comet services; //" "$s/profile/noor.md"; rm -f "$s/profile/noor.md.bak"'
tamper "[NON-NEGOTIABLE] file archived" "file carrying [NON-NEGOTIABLE] was archived: feedback/preferences.md" \
  'mkdir -p "$s/archive/feedback"; if command -v sha256sum >/dev/null 2>&1; then h=$(sha256sum "$s/feedback/preferences.md" | cut -d" " -f1); else h=$(shasum -a 256 "$s/feedback/preferences.md" | cut -d" " -f1); fi;
   printf -- "- 2026-09-12 archive | from: feedback/preferences.md | to: archive/feedback/preferences.md | sha256: %s | reason: test | spine-entry: - [Preferences](feedback/preferences.md) — output and interaction rules incl. the non-negotiables. Read when shaping output for Noor.\n" "$h" >> "$s/archive/LEDGER.md";
   mv "$s/feedback/preferences.md" "$s/archive/feedback/preferences.md";
   sed -i.bak "/feedback\/preferences.md/d" "$s/SPINE.md" "$s/CATALOG.md"; rm -f "$s/SPINE.md.bak" "$s/CATALOG.md.bak";
   sed -i.bak "s/rebuilt: 2026-09-11/rebuilt: 2026-09-12/" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak";
   printf -- "- archive/feedback/preferences.md | Output and interaction preferences | archived 2026-09-12 | reason: test | from feedback/preferences.md | hook: output and interaction rules incl. the non-negotiables. Read when shaping output for Noor.\n" >> "$s/CATALOG.md"'
tamper "catalog pinned flag disagrees with the file" "catalog row says pinned but projects/beacon.md is not" \
  'sed -i.bak "s/^\(- projects\/beacon.md .*\)$/\1 | pinned/" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'
tamper "catalog validated date disagrees with the file" "catalog validated date wrong for projects/comet.md" \
  'sed -i.bak "s/| validated 2026-05-06 | pinned/| validated 1999-01-01 | pinned/" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'
tamper "dangling split_from" "split_from target missing: craft/ghost.md" \
  'sed -i.bak "s|^split_from: craft/testing.md|split_from: craft/ghost.md|" "$s/craft/testing-2.md"; rm -f "$s/craft/testing-2.md.bak"'
tamper "read_with into the local/ overlay" "read_with into local/ overlay: local/ops/vpn.md" \
  'sed -i.bak "s|^read_with: \[ops/deploy.md\]|read_with: [ops/deploy.md, local/ops/vpn.md]|" "$s/projects/beacon.md"; rm -f "$s/projects/beacon.md.bak"'
tamper "after-shaped store with one entry over the cap" "entry over 400 bytes" \
  '{ printf -- "- [Fat](ops/deploy.md) — "; head -c 420 /dev/zero | tr "\0" "y"; printf "\n"; } >> "$s/SPINE.md"'

echo "== round-four cases =="
tamper "deleted legacy archive file" "archive file deleted: archive/old-warehouse-notes.md" \
  'rm "$s/archive/old-warehouse-notes.md"; sed -i.bak "/old-warehouse-notes.md/d" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'
tamper "nested archive file labelled legacy with the ledger removed" "nested archive file labelled legacy: archive/projects/atlas.md" \
  'rm "$s/archive/LEDGER.md"; sed -i.bak "s|^\(- archive/projects/atlas.md .*\)$|\1 \| legacy|" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'
tamper "dated [NON-NEGOTIABLE date] block demoted to evidence only" "protected block line not in active/archive" \
  'mkdir -p "$s/evidence/projects"; grep "NON-NEGOTIABLE 2026-01-15\] Reconciliation" "$s/projects/comet.md" > "$s/e.tmp";
   sed -i.bak "/NON-NEGOTIABLE 2026-01-15\] Reconciliation/d" "$s/projects/comet.md"; rm -f "$s/projects/comet.md.bak";
   { printf -- "---\nevidence_for: projects/comet.md\n---\n"; cat "$s/e.tmp"; } > "$s/evidence/projects/comet.md"; rm -f "$s/e.tmp";
   printf -- "- evidence/projects/comet.md | for projects/comet.md | 1 entries\n" >> "$s/CATALOG.md"'
# repeated migration: --before is itself a migrated store; a line dropped from an existing twin must be caught
tmp=$(mktemp -d); cp -r store-after "$tmp/s"
awk "/2026-05-11 observe/ {next} {print}" "$tmp/s/evidence/craft/testing.md" > "$tmp/e.tmp"; mv "$tmp/e.tmp" "$tmp/s/evidence/craft/testing.md"
sed -i.bak "s/| 30 entries/| 29 entries/" "$tmp/s/CATALOG.md"; rm -f "$tmp/s/CATALOG.md.bak"
out=$(bash "$CHECK" "$tmp/s" --before store-after 2>&1); rc=$?
{ [ $rc -ne 0 ] && echo "$out" | grep -Fq -- "line lost from evidence/craft/testing.md"; } && ok "line dropped from a pre-existing evidence twin (repeated migration)" || { bad "evidence twin loss missed (rc=$rc)"; echo "$out" | sed 's/^/       /'; }
rm -rf "$tmp"

echo "== round-five cases =="
tamper "heading-form [DIRECTIVE date] section demoted to evidence only" "protected block line not in active/archive (ops/deploy.md)" \
  'mkdir -p "$s/evidence/ops"; sed -n "/^## \[DIRECTIVE 2026-07-20\]/,\$p" "$s/ops/deploy.md" > "$s/sec.tmp";
   sed -i.bak "/^## \[DIRECTIVE 2026-07-20\]/,\$d" "$s/ops/deploy.md"; rm -f "$s/ops/deploy.md.bak";
   { printf -- "---\nevidence_for: ops/deploy.md\n---\n"; cat "$s/sec.tmp"; } > "$s/evidence/ops/deploy.md"; rm -f "$s/sec.tmp";
   printf -- "- evidence/ops/deploy.md | for ops/deploy.md | 2 entries\n" >> "$s/CATALOG.md"'
tamper "evidence_for disagrees with the twin path" "evidence_for disagrees with the twin's path: evidence/craft/testing.md says ops/deploy.md" \
  'sed -i.bak "s|^evidence_for: craft/testing.md|evidence_for: ops/deploy.md|" "$s/evidence/craft/testing.md"; rm -f "$s/evidence/craft/testing.md.bak"'
expect_pass "archive one target of a merged line by pointer removal (derived ledger entry)" \
  'mkdir -p "$s/archive/projects";
   if command -v sha256sum >/dev/null 2>&1; then h=$(sha256sum "$s/projects/delta.md" | cut -d" " -f1); else h=$(shasum -a 256 "$s/projects/delta.md" | cut -d" " -f1); fi;
   hook="Beacon notification service (push-provider fallback chain) and Delta webhook relay (retries, dead-letter). Read when working in the beacon or delta repos.";
   printf -- "- 2026-09-12 archive | from: projects/delta.md | to: archive/projects/delta.md | sha256: %s | reason: past threshold, no validation observed | spine-entry: - [Delta](projects/delta.md) — %s\n" "$h" "$hook" >> "$s/archive/LEDGER.md";
   mv "$s/projects/delta.md" "$s/archive/projects/delta.md";
   sed -i.bak "s| + \[Delta\](projects/delta.md)||" "$s/SPINE.md"; rm -f "$s/SPINE.md.bak";
   sed -i.bak "/^- projects\/delta.md |/d; s/rebuilt: 2026-09-11/rebuilt: 2026-09-12/" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak";
   printf -- "- archive/projects/delta.md | Delta webhook relay — retries and dead-letter handling | archived 2026-09-12 | reason: past threshold, no validation observed | from projects/delta.md | hook: %s\n" "$hook" >> "$s/CATALOG.md"'

echo "== round six: lossless append keeps pre-existing duplicates (combined multiset) =="
DUP='- 2026-05-11 observe: Noor rewrote a sleep(2) into a poll with a 5 s timeout without being asked'
with_before "duplicate in principle file and twin collapsed to one copy" "line lost from craft/testing.md (before x2, after x1)" store-after \
  'printf -- "%s\n" "$DUP" >> "$b/craft/testing.md"' \
  ':'
with_before "duplicate in principle file and twin survives twice (append skips only lines this plan wrote)" PASS store-after \
  'printf -- "%s\n" "$DUP" >> "$b/craft/testing.md"' \
  'printf -- "%s\n" "$DUP" >> "$s/evidence/craft/testing.md"; sed -i.bak "s/| 30 entries/| 31 entries/" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'

echo "== round six: path containment (D10) =="
tamper "read_with with a .. traversal" "uncontained path in projects/beacon.md read_with: ../../../../etc/hosts" \
  'sed -i.bak "s|^read_with: \[ops/deploy.md\]|read_with: [ops/deploy.md, ../../../../etc/hosts]|" "$s/projects/beacon.md"; rm -f "$s/projects/beacon.md.bak"'
tamper "ledger restore to an absolute path" "uncontained path in archive/LEDGER.md to: /etc/hosts" \
  'printf -- "- 2026-09-10 restore | from: archive/projects/atlas.md | to: /etc/hosts | sha256: 0 | reason: test\n" >> "$s/archive/LEDGER.md"'
tamper "ledger archive from a .. path" "uncontained path in archive/LEDGER.md from: ../x.md" \
  'printf -- "- 2026-09-10 archive | from: ../x.md | to: archive/../x.md | sha256: 0 | reason: test | spine-entry: - [X](../x.md) — x\n" >> "$s/archive/LEDGER.md"'
tamper "split_from starting with ~" "uncontained path in craft/testing-2.md split_from: ~/.ssh/config" \
  'sed -i.bak "s|^split_from: craft/testing.md|split_from: ~/.ssh/config|" "$s/craft/testing-2.md"; rm -f "$s/craft/testing-2.md.bak"'
tamper "catalog row with a .. path" "uncontained path in CATALOG.md: ../outside.md" \
  'printf -- "- ../outside.md | outside the store\n" >> "$s/CATALOG.md"'
tamper "SPINE pointer to an absolute path" "uncontained path in SPINE.md: /etc/hosts.md" \
  'printf -- "- [Hosts](/etc/hosts.md) — hosts.\n" >> "$s/SPINE.md"'
tmp=$(mktemp -d); cp -r store-after "$tmp/s"; ln -s /etc/hosts "$tmp/s/ops/hosts.md" 2>/dev/null
if [ -L "$tmp/s/ops/hosts.md" ]; then
  out=$(bash "$CHECK" "$tmp/s" --before store-before 2>&1); rc=$?
  { [ $rc -ne 0 ] && echo "$out" | grep -Fq -- "symlink in store: ops/hosts.md"; } && ok "symlink out of the store" || { bad "symlink missed (rc=$rc)"; echo "$out" | sed 's/^/       /'; }
else echo "  skip symlink case (this filesystem does not create symlinks)"; fi
rm -rf "$tmp"

echo "== round six: ledger syntax, catalog timestamps, wrapped SPINE entries =="
tamper "unknown ledger event word" "unknown ledger event 'purge'" \
  'printf -- "- 2026-09-10 purge | from: projects/beacon.md | to: archive/projects/beacon.md | reason: test\n" >> "$s/archive/LEDGER.md"'
tamper "ledger line without a leading date" "malformed ledger line" \
  'printf -- "- yesterday archive | from: projects/beacon.md | to: archive/projects/beacon.md | reason: test\n" >> "$s/archive/LEDGER.md"'
tamper "ledger archive line whose to: is not archive/<from>" "ledger archive line must move X to archive/X" \
  'printf -- "- 2026-09-10 archive | from: projects/beacon.md | to: archive/projects/comet.md | sha256: 0 | reason: test | spine-entry: - [B](projects/beacon.md) — b\n" >> "$s/archive/LEDGER.md"'
tamper "ledger restore line whose from: is not archive/<to>" "ledger restore line must move archive/X to X" \
  'printf -- "- 2026-09-10 restore | from: archive/projects/atlas.md | to: projects/beacon.md | sha256: 0 | reason: test\n" >> "$s/archive/LEDGER.md"'
tamper "same-day ledger event after a timestamped rebuild" "catalog stale: rebuilt 2026-09-11T10:00:00Z" \
  'sed -i.bak "s/^- 2026-09-11 archive/- 2026-09-11T12:00:00Z archive/" "$s/archive/LEDGER.md"; sed -i.bak "s/rebuilt: 2026-09-11/rebuilt: 2026-09-11T10:00:00Z/" "$s/CATALOG.md"; rm -f "$s/archive/LEDGER.md.bak" "$s/CATALOG.md.bak"'
expect_pass "timestamped rebuild after a same-day timestamped ledger event" \
  'sed -i.bak "s/^- 2026-09-11 archive/- 2026-09-11T12:00:00Z archive/" "$s/archive/LEDGER.md"; sed -i.bak "s/rebuilt: 2026-09-11/rebuilt: 2026-09-11T13:00:00Z/" "$s/CATALOG.md"; rm -f "$s/archive/LEDGER.md.bak" "$s/CATALOG.md.bak"'
tamper "wrapped SPINE entry over the cap only with its continuation line" "entry over 400 bytes" \
  '{ printf -- "- [Wrapped](ops/deploy.md) — "; head -c 250 /dev/zero | tr "\0" "y"; printf "\n  "; head -c 200 /dev/zero | tr "\0" "z"; printf "\n"; } >> "$s/SPINE.md"'

echo "== round six: --before is itself a migrated store =="
with_before "re-archive after restore and edit (ledger checksum), before = migrated store" PASS store-after ':' \
  'L="$s/archive/LEDGER.md";
   printf -- "- 2026-09-12 restore | from: archive/projects/atlas.md | to: projects/atlas.md | sha256: %s | reason: user request\n" "$(shaf "$s/archive/projects/atlas.md")" >> "$L";
   printf -- "\n- 2026-09-12 observe: cutover rescheduled to Q1\n" >> "$s/archive/projects/atlas.md";
   entry=$(sed -n "s/.*| spine-entry: //p" "$L" | head -1);
   printf -- "- 2026-09-13 archive | from: projects/atlas.md | to: archive/projects/atlas.md | sha256: %s | reason: past threshold, no validation observed | spine-entry: %s\n" "$(shaf "$s/archive/projects/atlas.md")" "$entry" >> "$L";
   sed -i.bak "s/rebuilt: 2026-09-11/rebuilt: 2026-09-13/" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'
with_before "archived file edited without a ledger line, before = migrated store" "archived file differs from original and from its ledger checksum: archive/projects/atlas.md" store-after ':' \
  'printf "\n" >> "$s/archive/projects/atlas.md"'
with_before "evidence twin deleted" "evidence twin deleted: evidence/craft/testing.md" store-after ':' \
  'rm "$s/evidence/craft/testing.md"; sed -i.bak "/evidence\/craft\/testing.md/d" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'

echo "== round six: legacy archives nested inside a tier directory =="
NESTED='---
scope: Old testing notes (rewritten by an earlier compaction)
recall_count: 0
---
- Old: integration suite ran nightly only.'
with_before "nested <tier>/archive/ file adopted byte-identically at archive/legacy/" PASS store-before \
  'mkdir -p "$b/craft/archive"; printf "%s\n" "$NESTED" > "$b/craft/archive/old-testing.md"' \
  'mkdir -p "$s/archive/legacy/craft/archive"; printf "%s\n" "$NESTED" > "$s/archive/legacy/craft/archive/old-testing.md";
   printf -- "- archive/legacy/craft/archive/old-testing.md | Old testing notes | legacy\n" >> "$s/CATALOG.md"'
with_before "nested legacy archive left inside the tier directory" "legacy archive inside a tier directory: craft/archive/old-testing.md" store-before \
  'mkdir -p "$b/craft/archive"; printf "%s\n" "$NESTED" > "$b/craft/archive/old-testing.md"' \
  'mkdir -p "$s/craft/archive"; printf "%s\n" "$NESTED" > "$s/craft/archive/old-testing.md"'
with_before "nested legacy archive dropped by migration" "nested legacy archive not adopted: craft/archive/old-testing.md" store-before \
  'mkdir -p "$b/craft/archive"; printf "%s\n" "$NESTED" > "$b/craft/archive/old-testing.md"' ':'
with_before "nested legacy archive adopted but rewritten" "legacy archive file changed: archive/legacy/craft/archive/old-testing.md" store-before \
  'mkdir -p "$b/craft/archive"; printf "%s\n" "$NESTED" > "$b/craft/archive/old-testing.md"' \
  'mkdir -p "$s/archive/legacy/craft/archive"; printf "%s\nrewritten\n" "$NESTED" > "$s/archive/legacy/craft/archive/old-testing.md";
   printf -- "- archive/legacy/craft/archive/old-testing.md | Old testing notes | legacy\n" >> "$s/CATALOG.md"'

echo "== round six: dedicated cases for the remaining checker branches =="
tamper "SPINE.md missing" "SPINE.md missing" 'rm "$s/SPINE.md"'
tamper "SPINE over the line cap" "lines (max 80)" \
  'i=0; while [ $i -lt 70 ]; do i=$((i+1)); echo "## Pad $i"; done >> "$s/SPINE.md"'
tamper "SPINE over the byte cap with every entry under its cap" "bytes (max 16000)" \
  'i=0; while [ $i -lt 45 ]; do i=$((i+1)); printf -- "- [Pad](ops/deploy.md) — "; head -c 350 /dev/zero | tr "\0" "p"; printf "\n"; done >> "$s/SPINE.md"'
tamper "SPINE without the catalog line" "SPINE has no catalog line" \
  'sed -i.bak "/](CATALOG.md)/d" "$s/SPINE.md"; rm -f "$s/SPINE.md.bak"'
tamper "SPINE pointer to a missing file" "SPINE pointer to missing file: craft/ghost.md" \
  'printf -- "- [Ghost](craft/ghost.md) — ghost.\n" >> "$s/SPINE.md"'
tamper "active file without a SPINE pointer" "active file has no SPINE pointer: ops/extra.md" \
  'printf -- "---\nscope: extra\nlast_validated: 2026-09-01\n---\n- a rule\n" > "$s/ops/extra.md"; printf -- "- ops/extra.md | extra | validated 2026-09-01\n" >> "$s/CATALOG.md"'
tamper "CATALOG.md missing" "CATALOG.md missing" 'rm "$s/CATALOG.md"'
tamper "file missing from the catalog" "file not in catalog: ops/deploy.md" \
  'sed -i.bak "/^- ops\/deploy.md |/d" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'
tamper "catalog row for a missing file" "catalog line points at missing file: ops/ghost.md" \
  'printf -- "- ops/ghost.md | ghost | validated 2026-09-01\n" >> "$s/CATALOG.md"'
tamper "catalog validated date for an undated file" "catalog claims a validated date for undated file ops/undated.md" \
  'printf -- "---\nscope: undated\n---\n- a rule\n" > "$s/ops/undated.md"; printf -- "- [Undated](ops/undated.md) — undated.\n" >> "$s/SPINE.md";
   printf -- "- ops/undated.md | undated | validated 2026-09-01\n" >> "$s/CATALOG.md"'
tamper "catalog row lacks pinned for a pinned file" "catalog row lacks pinned for projects/comet.md" \
  'sed -i.bak "s/| validated 2026-05-06 | pinned/| validated 2026-05-06/" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'
tamper "catalog evidence count wrong" "catalog count wrong for evidence/craft/testing.md" \
  'sed -i.bak "s/| 30 entries/| 31 entries/" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'
tamper "evidence twin without evidence_for" "evidence/craft/testing.md has no evidence_for" \
  'sed -i.bak "/^evidence_for:/d" "$s/evidence/craft/testing.md"; rm -f "$s/evidence/craft/testing.md.bak"'
tamper "flat archive file not labelled legacy" "flat archive file must be labelled legacy in the catalog: archive/old-warehouse-notes.md" \
  'sed -i.bak "s/^\(- archive\/old-warehouse-notes.md .*\) | legacy$/\1/" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'
tamper "archived row without from" "archived row lacks 'from': archive/projects/atlas.md" \
  'sed -i.bak "s/ | from projects\/atlas.md//" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'
tamper "archived row without hook" "archived row lacks 'hook': archive/projects/atlas.md" \
  'sed -i.bak "s/^\(- archive\/projects\/atlas.md .*\) | hook: .*$/\1/" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'
tamper "ledger missing with a non-legacy archive" "archive/LEDGER.md missing but archive/projects/atlas.md is not legacy" \
  'rm "$s/archive/LEDGER.md"'
tamper "no ledger archive event for an archived file" "no ledger archive event for: archive/projects/atlas.md" \
  'sed -i.bak "/ archive | from: projects\/atlas.md/d" "$s/archive/LEDGER.md"; rm -f "$s/archive/LEDGER.md.bak"'
tamper "catalog hook differs from the ledger hook" "catalog hook differs from ledger spine-entry hook: archive/projects/atlas.md" \
  'sed -i.bak "s/| hook: Atlas data-platform/| hook: Atlas Data-platform/" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'
tamper "ledger restore event for a file still archived" "ledger says restored but tree disagrees: projects/atlas.md" \
  'printf -- "- 2026-09-10 restore | from: archive/projects/atlas.md | to: projects/atlas.md | sha256: 0 | reason: user request\n" >> "$s/archive/LEDGER.md"'
tamper "catalog without a rebuilt stamp" "catalog has no rebuilt: stamp" \
  'sed -i.bak "s/ rebuilt: 2026-09-11//" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'
tamper "tier file over the line cap" "ops/deploy.md has" \
  'i=0; while [ $i -lt 60 ]; do i=$((i+1)); echo "- pad $i"; done >> "$s/ops/deploy.md"'
tamper "tier file over the byte cap" "ops/deploy.md is" \
  '{ head -c 7000 /dev/zero | tr "\0" "b"; printf "\n"; } >> "$s/ops/deploy.md"'
tamper "pinned file moved" "pinned file was moved: projects/comet.md" \
  'mkdir -p "$s/archive/projects"; mv "$s/projects/comet.md" "$s/archive/projects/comet.md"'
tamper "legacy archive file changed" "legacy archive file changed: archive/old-warehouse-notes.md" \
  'printf "rewritten\n" >> "$s/archive/old-warehouse-notes.md"'
tamper "archived file with no original" "archived file has no original: archive/projects/zeta.md" \
  'printf -- "---\nscope: zeta\n---\n- zeta\n" > "$s/archive/projects/zeta.md";
   printf -- "- 2026-09-10 archive | from: projects/zeta.md | to: archive/projects/zeta.md | sha256: %s | reason: test | spine-entry: - [Zeta](projects/zeta.md) — zeta.\n" "$(shaf "$s/archive/projects/zeta.md")" >> "$s/archive/LEDGER.md";
   printf -- "- archive/projects/zeta.md | zeta | archived 2026-09-10 | reason: test | from projects/zeta.md | hook: zeta.\n" >> "$s/CATALOG.md"'

echo "== round seven: unledgered archive/<tier>/ files (the real-store shape) are adopted =="
tamper "unledgered archive/<tier>/ file left in place" "unledgered archive not adopted: archive/projects/ember.md (expected archive/legacy/archive/projects/ember.md)" \
  'mv "$s/archive/legacy/archive/projects/ember.md" "$s/archive/projects/ember.md"; sed -i.bak "s|^- archive/legacy/archive/projects/ember.md |- archive/projects/ember.md |" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'
tamper "unledgered archive adopted but rewritten" "legacy archive file changed: archive/legacy/archive/projects/ember.md" \
  'printf "rewritten\n" >> "$s/archive/legacy/archive/projects/ember.md"'
tamper "legacy archive file with no original" "archived file has no original: archive/stray.md" \
  'printf -- "---\nscope: stray\n---\n- stray\n" > "$s/archive/stray.md"; printf -- "- archive/stray.md | stray | legacy\n" >> "$s/CATALOG.md"'

echo "== round seven: a literal | in a free-text field is written \\| and parsed from the left =="
expect_pass "escaped \| in a ledger reason and in a hook (ledger and catalog)" \
  'sed -i.bak "/^- 2026-09-11 archive/s/reason: past threshold, no validation observed/reason: past threshold \\\\| no validation observed/; /^- 2026-09-11 archive/s/\$/ \\\\| see also Comet/" "$s/archive/LEDGER.md";
   sed -i.bak "/^- archive\/projects\/atlas.md /s/reason: past threshold, no validation observed/reason: past threshold \\\\| no validation observed/; /^- archive\/projects\/atlas.md /s/\$/ \\\\| see also Comet/" "$s/CATALOG.md";
   rm -f "$s/archive/LEDGER.md.bak" "$s/CATALOG.md.bak"'
tamper "unescaped | inside a spine-entry hook forges a to: field" "unescaped ' | ' inside a free-text field of archive/LEDGER.md" \
  'sed -i.bak "/^- 2026-09-11 archive/s/\$/ | to: archive\/projects\/comet.md/" "$s/archive/LEDGER.md";
   sed -i.bak "/^- archive\/projects\/atlas.md /s/\$/ | to: archive\/projects\/comet.md/" "$s/CATALOG.md";
   rm -f "$s/archive/LEDGER.md.bak" "$s/CATALOG.md.bak"'
tamper "unescaped | splits a catalog scope into a bogus field" "unescaped ' | ' inside a free-text field of CATALOG.md" \
  'sed -i.bak "s/^- projects\/beacon.md | Beacon notification service/- projects\/beacon.md | Beacon | notification service/" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'

echo "== cycle 2 round one: the documented backup set is enough for the self-check =="
# section 3 step 2: SPINE.md, CATALOG.md if present, every tier directory, evidence/**, archive/** (incl. LEDGER.md) — and nothing else
tmp=$(mktemp -d); mkdir "$tmp/backup"
for x in SPINE.md CATALOG.md craft ops profile projects feedback evidence archive; do [ -e "store-before/$x" ] && cp -r "store-before/$x" "$tmp/backup/"; done
out=$(bash "$CHECK" store-after --before "$tmp/backup" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "store-after passes against exactly the documented backup set" || { bad "backup-set check failed (rc=$rc)"; echo "$out" | sed 's/^/       /'; }
rm -rf "$tmp"

echo "== cycle 2 round one: an old client archives on a migrated store =="
FERN='---
archived_from: projects/fern.md
archived_on: 2026-09-15
reason: stale
recall_count: 0
---
# Fern (archived by an old client, no ledger line)'
with_before "unledgered archive/<tier>/ file on a migrated store is reported pending adoption" "no ledger archive event for: archive/projects/fern.md (unledgered: pending adoption by migrate-store)" store-after \
  'printf "%s\n" "$FERN" > "$b/archive/projects/fern.md"' \
  'printf "%s\n" "$FERN" > "$s/archive/projects/fern.md"; printf -- "- archive/projects/fern.md | Fern | archived 2026-09-15 | from projects/fern.md | hook: Fern\n" >> "$s/CATALOG.md"'
with_before "repeated migrate-store adopts the old-client archive to archive/legacy/" PASS store-after \
  'printf "%s\n" "$FERN" > "$b/archive/projects/fern.md"' \
  'mkdir -p "$s/archive/legacy/archive/projects"; printf "%s\n" "$FERN" > "$s/archive/legacy/archive/projects/fern.md";
   printf -- "- archive/legacy/archive/projects/fern.md | Fern (adopted from archive/projects/fern.md) | legacy\n" >> "$s/CATALOG.md"'

echo "== cycle 2 round one: pointer extraction and field anchoring =="
tamper "pointer only inside an HTML comment" "active file has no SPINE pointer: ops/extra.md" \
  'printf -- "---\nscope: extra\nlast_validated: 2026-09-01\n---\n- a rule\n" > "$s/ops/extra.md"; printf -- "- ops/extra.md | extra | validated 2026-09-01\n" >> "$s/CATALOG.md";
   printf -- "<!-- see [Extra](ops/extra.md) -->\n" >> "$s/SPINE.md"'
tamper "catalog segment that merely starts with oversize" "unescaped ' | ' inside a free-text field of CATALOG.md" \
  'sed -i.bak "s/^\(- projects\/beacon.md .*\)$/\1 | oversized notes/" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'

echo "== #78 handoff: retrieval markers never move to evidence =="
tamper "[PROVISIONAL] bullet demoted to evidence only" "protected block line not in active/archive (projects/beacon.md): - [PROVISIONAL]" \
  'mkdir -p "$s/evidence/projects"; grep "PROVISIONAL\] Email digest" "$s/projects/beacon.md" > "$s/e.tmp";
   sed -i.bak "/PROVISIONAL\] Email digest/d" "$s/projects/beacon.md"; rm -f "$s/projects/beacon.md.bak";
   { printf -- "---\nevidence_for: projects/beacon.md\n---\n"; cat "$s/e.tmp"; } > "$s/evidence/projects/beacon.md"; rm -f "$s/e.tmp";
   printf -- "- evidence/projects/beacon.md | for projects/beacon.md | 1 entries\n" >> "$s/CATALOG.md"'
tamper "dated [UPDATED date] bullet demoted to evidence only" "protected block line not in active/archive (ops/deploy.md): - [UPDATED 2026-07-20]" \
  'mkdir -p "$s/evidence/ops"; grep "UPDATED 2026-07-20\]" "$s/ops/deploy.md" > "$s/e.tmp";
   sed -i.bak "/UPDATED 2026-07-20\]/d" "$s/ops/deploy.md"; rm -f "$s/ops/deploy.md.bak";
   { printf -- "---\nevidence_for: ops/deploy.md\n---\n"; cat "$s/e.tmp"; } > "$s/evidence/ops/deploy.md"; rm -f "$s/e.tmp";
   printf -- "- evidence/ops/deploy.md | for ops/deploy.md | 1 entries\n" >> "$s/CATALOG.md"'

echo "== #78 handoff: ledger append order is date order =="
tamper "ledger line appended out of date order" "ledger events out of order: 2026-09-10 appended after 2026-09-12" \
  'entry=$(sed -n "s/.*| spine-entry: //p" "$s/archive/LEDGER.md" | head -1); h=$(shaf "$s/archive/projects/atlas.md");
   printf -- "- 2026-09-12 restore | from: archive/projects/atlas.md | to: projects/atlas.md | sha256: %s | reason: user request\n" "$h" >> "$s/archive/LEDGER.md";
   printf -- "- 2026-09-10 archive | from: projects/atlas.md | to: archive/projects/atlas.md | sha256: %s | reason: past threshold | spine-entry: %s\n" "$h" "$entry" >> "$s/archive/LEDGER.md";
   sed -i.bak "s/rebuilt: 2026-09-11/rebuilt: 2026-09-12/" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'
expect_pass "restore then re-archive appended in date order" \
  'entry=$(sed -n "s/.*| spine-entry: //p" "$s/archive/LEDGER.md" | head -1); h=$(shaf "$s/archive/projects/atlas.md");
   printf -- "- 2026-09-12 restore | from: archive/projects/atlas.md | to: projects/atlas.md | sha256: %s | reason: user request\n" "$h" >> "$s/archive/LEDGER.md";
   printf -- "- 2026-09-12T18:00:00Z archive | from: projects/atlas.md | to: archive/projects/atlas.md | sha256: %s | reason: user request | spine-entry: %s\n" "$h" "$entry" >> "$s/archive/LEDGER.md";
   sed -i.bak "s/rebuilt: 2026-09-11/rebuilt: 2026-09-12T18:05:00Z/" "$s/CATALOG.md"; rm -f "$s/CATALOG.md.bak"'

echo "== #78 handoff: the catalog line is an entry line =="
tamper "catalog link only in prose, not on an entry line" "SPINE has no catalog line" \
  'sed -i.bak "s|^- \[Catalog\](CATALOG.md) — |See [Catalog](CATALOG.md) — |" "$s/SPINE.md"; rm -f "$s/SPINE.md.bak"'

echo "== #78 handoff: recall_count bumped by a 1.1 client is drift, not modification =="
# new archive ledger lines carry sha256-norm: (checksum with the frontmatter recall_count: line removed)
NORM_LEDGER='h=$(shaf "$s/archive/projects/atlas.md"); sed -i.bak "s/| sha256: $h |/| sha256: $h | sha256-norm: $h |/" "$s/archive/LEDGER.md"; rm -f "$s/archive/LEDGER.md.bak"'
BUMP='sed -i.bak "s/^staleness_threshold: 90$/staleness_threshold: 90\nrecall_count: 1/" "$s/archive/projects/atlas.md"; rm -f "$s/archive/projects/atlas.md.bak"'
expect_pass "archived file whose only change is a bumped recall_count (sha256-norm matches)" "$NORM_LEDGER; $BUMP"
tamper "bumped recall_count plus a real edit" "ledger sha256 does not match archived file: archive/projects/atlas.md" \
  "$NORM_LEDGER; $BUMP; printf -- \"- edited\\n\" >> \"\$s/archive/projects/atlas.md\""
tamper "bumped recall_count on a ledger line without sha256-norm (1.2 lines always carry it)" "ledger sha256 does not match archived file: archive/projects/atlas.md" "$BUMP"
expect_pass "legacy archive whose only change is a bumped recall_count" \
  'sed -i.bak "s/^recall_count: 1$/recall_count: 2/" "$s/archive/legacy/archive/projects/ember.md"; rm -f "$s/archive/legacy/archive/projects/ember.md.bak"'

echo "== #78: the shipped helper's --print-catalog output is a catalog the checker accepts =="
REBUILD='bash "$CHECK" --print-catalog "$s" > "$s/cat.tmp" && mv "$s/cat.tmp" "$s/CATALOG.md"'
expect_pass "rebuilt catalog of store-after" "$REBUILD"
PIPE_SCOPE='sed -i.bak "s/^scope: Delta webhook relay — retries and dead-letter handling$/scope: Delta webhook relay | retries and dead-letter/" "$X/projects/delta.md"; rm -f "$X/projects/delta.md.bak"'
with_before "rebuilt catalog after a pipe in a scope and an escaped ledger reason" PASS store-after \
  "X=\$b; $PIPE_SCOPE" \
  "X=\$s; $PIPE_SCOPE"'; sed -i.bak "/^- 2026-09-11 archive/s/reason: past threshold, no validation observed/reason: past threshold \\\\| no validation observed/" "$s/archive/LEDGER.md"; rm -f "$s/archive/LEDGER.md.bak";
   grep -q "scope: Delta webhook relay | retries" "$s/projects/delta.md" && grep -q "past threshold \\\\| no" "$s/archive/LEDGER.md" || echo "SETUP FAILED" > "$s/ops/setup-failed.md"; '"$REBUILD"'; grep -q "Delta webhook relay \\\\| retries" "$s/CATALOG.md" || echo "ESCAPE MISSING" > "$s/ops/escape-missing.md"'
tmp=$(mktemp -d); cp -r store-after "$tmp/s"
out=$(bash "$CHECK" --hashes "$tmp/s/archive/projects/atlas.md"); want=$(shaf "$tmp/s/archive/projects/atlas.md")
sed -i.bak "s/^staleness_threshold: 90$/staleness_threshold: 90\nrecall_count: 3/" "$tmp/s/archive/projects/atlas.md"
out2=$(bash "$CHECK" --hashes "$tmp/s/archive/projects/atlas.md")
{ echo "$out" | grep -qx "sha256 $want" && echo "$out" | grep -qx "sha256-norm $want" && echo "$out2" | grep -qx "sha256-norm $want" && ! echo "$out2" | grep -qx "sha256 $want"; } \
  && ok "--hashes prints raw and recall_count-normalised checksums" || { bad "--hashes output wrong"; echo "$out"; echo "$out2"; }
rm -rf "$tmp"

echo "== #78 handoff: legacy restore is a copy; the legacy file stays =="
LEGACY_RESTORE='L="$s/archive/legacy/archive/projects/ember.md";
   { printf -- "---\nscope: Ember carrier-rate import (restored from a legacy archive)\nrestored_from: archive/legacy/archive/projects/ember.md\nlast_updated: 2026-09-12\n---\n"; awk "f>=2{print} /^---\$/{f++}" "$L"; } > "$s/projects/ember.md";
   printf -- "- [Ember](projects/ember.md) — Ember carrier-rate import, restored from the legacy archive. Read when working on carrier rates.\n" >> "$s/SPINE.md"'
expect_pass "legacy restore copies the content to projects/ember.md" "$LEGACY_RESTORE; $REBUILD"
tamper "legacy restore done as a move (legacy file gone)" "archive file deleted: archive/projects/ember.md" \
  "$LEGACY_RESTORE; rm \"\$s/archive/legacy/archive/projects/ember.md\"; $REBUILD"

echo "== #78 round one: the local overlay's SPINE points only inside local/ =="
LOCAL_OK='mkdir -p "$s/local/ops"; printf -- "---\nscope: vpn\n---\n- office VPN profile\n" > "$s/local/ops/vpn.md";
   printf -- "# Local index\n\n- [VPN](local/ops/vpn.md) — office VPN on this laptop.\n" > "$s/local/SPINE.md"'
expect_pass "local/SPINE.md pointing inside local/ (never cataloged)" "$LOCAL_OK"
tamper "local/SPINE.md pointing out of the overlay" "local/SPINE.md may point only inside local/: ops/deploy.md" \
  "$LOCAL_OK"'; printf -- "- [Deploy](ops/deploy.md) — shared file.\n" >> "$s/local/SPINE.md"'
tamper "local/SPINE.md with a .. traversal" "local/SPINE.md may point only inside local/: local/../../x.md" \
  "$LOCAL_OK"'; printf -- "- [X](local/../../x.md) — x.\n" >> "$s/local/SPINE.md"'
tamper "local/SPINE.md pointer to a missing file" "local/SPINE.md pointer to missing file: local/ops/ghost.md" \
  "$LOCAL_OK"'; printf -- "- [Ghost](local/ops/ghost.md) — ghost.\n" >> "$s/local/SPINE.md"'
tamper "synced SPINE pointing into local/" "uncontained path in SPINE.md: local/ops/vpn.md" \
  "$LOCAL_OK"'; printf -- "- [VPN](local/ops/vpn.md) — vpn.\n" >> "$s/SPINE.md"'

echo "== #78 round one: a new store is born in the files-only layout =="
tmp=$(mktemp -d); mkdir -p "$tmp/s"
printf -- "# Distill Knowledge Index\n\n<!-- managed -->\n\n- [Catalog](CATALOG.md) — complete inventory; not loaded at start.\n" > "$tmp/s/SPINE.md"
printf -- "# Knowledge catalog\n\n<!-- Complete inventory, rebuilt by /distill. Not loaded at session start. rebuilt: 2026-09-23T10:00:00Z -->\n\n## active\n\n## archived\n\n## evidence\n" > "$tmp/s/CATALOG.md"
out=$(bash "$CHECK" "$tmp/s" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "an empty installer-shaped store passes" || { bad "empty installer-shaped store fails (rc=$rc)"; echo "$out" | sed 's/^/       /'; }
rm -rf "$tmp"

echo "== #78 round two: the evidence twin of a file a 1.1 client archived, adopted as legacy =="
EMBER_TWIN='mkdir -p "$s/evidence/projects"; printf -- "---\nevidence_for: projects/ember.md\n---\n- 2026-05-02 observe: rates import ran twice on the DST weekend\n" > "$s/evidence/projects/ember.md";
   printf -- "- evidence/projects/ember.md | for projects/ember.md | 1 entries\n" >> "$s/CATALOG.md"'
expect_pass "twin of an adopted legacy archive is accepted (noted, not an orphan)" "$EMBER_TWIN"
tmp=$(mktemp -d); cp -r store-after "$tmp/s"; ( s="$tmp/s"; eval "$EMBER_TWIN" )
out=$(bash "$CHECK" "$tmp/s" 2>&1)
echo "$out" | grep -Fq "note: evidence twin of an adopted legacy archive: evidence/projects/ember.md" && ok "the adopted twin is reported as a note" || { bad "no note for the adopted twin"; echo "$out" | sed 's/^/       /'; }
rm -rf "$tmp"
tamper "twin whose file exists nowhere, not even as an adopted legacy archive" "orphan evidence: evidence/projects/fern.md" \
  'mkdir -p "$s/evidence/projects"; printf -- "---\nevidence_for: projects/fern.md\n---\n- 2026-05-02 observe: x\n" > "$s/evidence/projects/fern.md";
   printf -- "- evidence/projects/fern.md | for projects/fern.md | 1 entries\n" >> "$s/CATALOG.md"'

echo
echo "files-only suite: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
