#!/usr/bin/env bash
# run-files-only-tests.sh — regression suite for the files-only memory redesign (#75).
#
# 1. store-before MUST fail C1, C2 and C3: the diagnosis (fat index, no catalog,
#    evidence inflating a tier file) reproduced on a synthetic store.
# 2. store-after --before store-before MUST pass everything: the redesign fixes the
#    diagnosis without losing a line, a checksum, a protected block, a hook or a pin.
# 3. Twenty-four tamper cases MUST be caught, each with a non-zero exit; one exemption
#    case (oversize:) and two restore cases (D7 restore obeying D1) MUST pass.
set -u
cd "$(dirname "$0")"
CHECK=./check-store.sh
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

echo "== store-before (expect C1, C2, C3 to fail) =="
out=$(bash "$CHECK" store-before 2>&1); rc=$?
echo "$out" | sed 's/^/     /'
[ $rc -ne 0 ] && ok "before store is rejected" || bad "before store was accepted"
for c in C1 C2 C3; do
  echo "$out" | grep -q "^$c FAIL" && ok "$c fails on before" || bad "$c did not fail on before"
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

echo
echo "files-only suite: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
