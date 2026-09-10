#!/usr/bin/env bash
# run-files-only-tests.sh — regression suite for the files-only memory redesign (#75).
#
# 1. store-before MUST fail C1, C2 and C3: that is the diagnosis (fat index, no
#    catalog, evidence inflating a tier file) reproduced on a synthetic store.
# 2. store-after --before store-before MUST pass everything: the redesign fixes the
#    diagnosis without losing a line, a checksum, a protected wording or a pin.
set -u
cd "$(dirname "$0")"
CHECK=./check-store.sh
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

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

echo "== negative: tamper an archived file, expect C4 to fail =="
tmp=$(mktemp -d); cp -r store-after "$tmp/s"; printf '\n' >> "$tmp/s/archive/projects/atlas.md"
out=$(bash "$CHECK" "$tmp/s" --before store-before 2>&1)
echo "$out" | grep -q "archived file differs" && ok "checksum tamper detected" || bad "checksum tamper missed"
rm -rf "$tmp"

echo "== negative: drop a protected line, expect C4 to fail =="
tmp=$(mktemp -d); cp -r store-after "$tmp/s"; sed -i.bak '/NON-NEGOTIABLE\] Never claim/d' "$tmp/s/feedback/preferences.md"; rm -f "$tmp/s/feedback/preferences.md.bak"
out=$(bash "$CHECK" "$tmp/s" --before store-before 2>&1)
echo "$out" | grep -q "line lost from feedback/preferences.md" && ok "lost protected line detected" || bad "lost protected line missed"
rm -rf "$tmp"

echo "== negative: remove a SPINE hook's wording everywhere, expect C4 to fail =="
tmp=$(mktemp -d); cp -r store-after "$tmp/s"; rm "$tmp/s/evidence/projects/atlas.md"; sed -i.bak '/evidence\/projects\/atlas.md/d' "$tmp/s/CATALOG.md"; rm -f "$tmp/s/CATALOG.md.bak"
out=$(bash "$CHECK" "$tmp/s" --before store-before 2>&1)
echo "$out" | grep -q "SPINE hook lost" && ok "lost SPINE hook detected" || bad "lost SPINE hook missed"
rm -rf "$tmp"

echo "== negative: dangling read_with target, expect C3 to fail =="
tmp=$(mktemp -d); cp -r store-after "$tmp/s"; sed -i.bak 's|^read_with: \[ops/deploy.md\]|read_with: [ops/deploy.md, ops/missing.md]|' "$tmp/s/projects/beacon.md"; rm -f "$tmp/s/projects/beacon.md.bak"
out=$(bash "$CHECK" "$tmp/s" 2>&1); rc=$?
{ [ $rc -ne 0 ] && echo "$out" | grep -q "read_with target missing: ops/missing.md"; } && ok "dangling read_with detected with non-zero exit" || bad "dangling read_with missed"
rm -rf "$tmp"

echo "== negative: protected line demoted to evidence only, expect C4 to fail =="
tmp=$(mktemp -d); cp -r store-after "$tmp/s"; mkdir -p "$tmp/s/evidence/projects"
grep 'NON-NEGOTIABLE\] Invoice records' "$tmp/s/projects/comet.md" >> "$tmp/s/evidence/projects/comet.md"
sed -i.bak '/NON-NEGOTIABLE\] Invoice records/d' "$tmp/s/projects/comet.md"; rm -f "$tmp/s/projects/comet.md.bak"
printf -- '- evidence/projects/comet.md | for projects/comet.md | 1 entries\n' >> "$tmp/s/CATALOG.md"
out=$(bash "$CHECK" "$tmp/s" --before store-before 2>&1); rc=$?
{ [ $rc -ne 0 ] && echo "$out" | grep -q "protected line not in active/archive"; } && ok "protected-to-evidence demotion detected with non-zero exit" || bad "protected-to-evidence demotion missed"
rm -rf "$tmp"

echo
echo "files-only suite: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
