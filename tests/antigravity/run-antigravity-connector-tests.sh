#!/usr/bin/env bash
# Test runner for aura-distill Antigravity (agy) connector (Bash)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
echo "Testing Antigravity connector in: $REPO_ROOT"

pass_count=0
fail_count=0

assert_true() {
    local condition="$1"
    local message="$2"
    if eval "$condition"; then
        echo "  [PASS] $message"
        pass_count=$((pass_count + 1))
    else
        echo "  [FAIL] $message"
        fail_count=$((fail_count + 1))
    fi
}

# Test 1: Check skills/distill/SKILL.md
assert_true "[[ -f '$REPO_ROOT/skills/distill/SKILL.md' ]]" "skills/distill/SKILL.md exists"
assert_true "grep -q 'name: distill' '$REPO_ROOT/skills/distill/SKILL.md'" "SKILL.md contains name: distill frontmatter"
assert_true "grep -q 'SPINE.md' '$REPO_ROOT/skills/distill/SKILL.md'" "SKILL.md references SPINE.md"

# Test 2: Check rules/distill-agy.md
assert_true "[[ -f '$REPO_ROOT/rules/distill-agy.md' ]]" "rules/distill-agy.md exists"
assert_true "grep -q 'SPINE.md' '$REPO_ROOT/rules/distill-agy.md'" "rules/distill-agy.md references SPINE.md"
assert_true "grep -q '\[NON-NEGOTIABLE\]' '$REPO_ROOT/rules/distill-agy.md'" "rules/distill-agy.md contains cognitive markers"

# Test 3: Check plugins/aura-distill/plugin.json
assert_true "[[ -f '$REPO_ROOT/plugins/aura-distill/plugin.json' ]]" "plugins/aura-distill/plugin.json exists"
assert_true "grep -q '\"name\": \"aura-distill\"' '$REPO_ROOT/plugins/aura-distill/plugin.json'" "plugin.json has name aura-distill"

# Test 4: Check bin/distill-recent-agy.sh
assert_true "[[ -f '$REPO_ROOT/bin/distill-recent-agy.sh' ]]" "bin/distill-recent-agy.sh exists"

echo ""
echo "Summary: $pass_count passed, $fail_count failed."
if [[ $fail_count -gt 0 ]]; then exit 1; fi
