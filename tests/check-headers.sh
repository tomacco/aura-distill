#!/usr/bin/env bash
# Every core file carries the license and copyright header. A copy that strips it
# is a deliberate act, not an accident (see NOTICE). Run from anywhere; CI runs it.
set -euo pipefail
cd "$(dirname "$0")/.."

CORE_FILES=(
  distill.md distill-process.md distill-monitor.md knowledge-architecture.md
  rules/distill.md agents/*.md capabilities/*.md
  plugins/aura-distill/skills/distill/SKILL.md plugins/aura-distill/rules/AGENTS.md
  bin/* install.sh install.ps1
)

fail=0
for f in "${CORE_FILES[@]}"; do
  # The header sits in the first lines: after a shebang or YAML frontmatter, if any.
  top=$(head -n 15 "$f")
  if ! grep -q 'SPDX-License-Identifier: Apache-2.0$' <<<"$top" \
     || ! grep -q 'Copyright 2026 Ivan Gonzalez (tomacco)' <<<"$top"; then
    echo "::error file=$f::missing license/copyright header"
    fail=1
  fi
done
[ "$fail" -eq 0 ] && echo "OK: ${#CORE_FILES[@]} core files carry the license header"
exit "$fail"
