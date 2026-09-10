#!/usr/bin/env bash
# run-files-only-tests.sh — regression suite for the files-only memory redesign (#75).
#
# 1. store-before MUST fail C1, C2 and C3: the diagnosis (fat index, no catalog,
#    evidence inflating a tier file) reproduced on a synthetic store.
# 2. store-after --before store-before MUST pass everything: the redesign fixes the
#    diagnosis without losing a line, a checksum, a protected block, a hook or a pin.
# 3. Ten tamper cases MUST be caught, each with a non-zero exit.
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
  'sed -i.bak "s/sha256: 12c18385/sha256: 00000000/" "$s/archive/LEDGER.md"; rm -f "$s/archive/LEDGER.md.bak"'
tamper "dropped protected line" "line lost from feedback/preferences.md" \
  'sed -i.bak "/NON-NEGOTIABLE\] Never claim/d" "$s/feedback/preferences.md"; rm -f "$s/feedback/preferences.md.bak"'
tamper "protected block demoted to evidence only" "protected block line not in active/archive" \
  'mkdir -p "$s/evidence/projects"; grep "NON-NEGOTIABLE\] Invoice records" "$s/projects/comet.md" > "$s/e.tmp";
   sed -i.bak "/NON-NEGOTIABLE\] Invoice records/d" "$s/projects/comet.md"; rm -f "$s/projects/comet.md.bak";
   { printf -- "---\nevidence_for: projects/comet.md\n---\n"; cat "$s/e.tmp"; } > "$s/evidence/projects/comet.md"; rm -f "$s/e.tmp";
   printf -- "- evidence/projects/comet.md | for projects/comet.md | 1 entries\n" >> "$s/CATALOG.md"'
tamper "lost SPINE hook" "SPINE hook lost" \
  'sed -i.bak "/^## Index detail/,\$d" "$s/profile/noor.md"; rm -f "$s/profile/noor.md.bak"'
tamper "dropped one of two identical lines (multiset)" "line lost from craft/testing.md (before x2, after x1)" \
  'awk "/last_validated: 2026-08-12/ && !seen {seen=1; next} {print}" "$s/craft/testing.md" > "$s/t.tmp"; mv "$s/t.tmp" "$s/craft/testing.md"'
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

echo
echo "files-only suite: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
