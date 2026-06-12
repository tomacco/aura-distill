#!/usr/bin/env bash
# Verifies the auto-bump workflow's run block against fixture copies.
# The script under test is extracted VERBATIM from bump-version.yml, so what
# is tested is exactly what GitHub Actions executes — no re-typed variant.
set -euo pipefail
cd "$(dirname "$0")"

t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT

cp VERSION install.sh install.ps1 README.md "$t/"
mkdir -p "$t/docs"
cp docs/header.svg docs/index.html "$t/docs/"

awk '/current=\$\(cat VERSION/,/GITHUB_ENV/' .github/workflows/bump-version.yml \
  | sed 's/^          //' | grep -v GITHUB_ENV > "$t/bump.sh"

expected=$(awk -F. '{printf "%d.%d.%d", $1, $2, $3 + 1}' VERSION)

(cd "$t" && bash bump.sh)

# bump.sh already fails loudly per file; this is an independent assertion.
for f in VERSION install.sh install.ps1 README.md docs/header.svg docs/index.html; do
  grep -q "$expected" "$t/$f" || { echo "FAIL: $f not bumped to $expected"; exit 1; }
done

echo "OK: all 6 files bumped to $expected"
