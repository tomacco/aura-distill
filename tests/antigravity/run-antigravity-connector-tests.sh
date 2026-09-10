#!/usr/bin/env bash
# Test runner for the aura-distill Antigravity (agy) connector (Bash).
# Mirrors run-antigravity-connector-tests.ps1: validates the plugin against
# Antigravity's documented discovery layout (plugin.json = marker; content at
# plugins/<name>/skills/<skill>/SKILL.md and plugins/<name>/rules/AGENTS.md).
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

PLUGIN="$REPO_ROOT/plugins/aura-distill"

# Test 1: plugin.json is a valid Antigravity marker (supported fields only)
assert_true "[[ -f '$PLUGIN/plugin.json' ]]" "plugins/aura-distill/plugin.json exists"
assert_true "grep -q '\"name\": \"aura-distill\"' '$PLUGIN/plugin.json'" "plugin.json has name aura-distill"
assert_true "! grep -Eq '\"(skills|rules|version|author|repository|license)\"' '$PLUGIN/plugin.json'" "plugin.json uses only Antigravity-supported fields"

# Test 2: skill sits at the DISCOVERED path inside the plugin
assert_true "[[ -f '$PLUGIN/skills/distill/SKILL.md' ]]" "plugins/aura-distill/skills/distill/SKILL.md exists (discovery path)"
assert_true "grep -q 'name: distill' '$PLUGIN/skills/distill/SKILL.md'" "SKILL.md contains name: distill frontmatter"
assert_true "grep -q 'SPINE.md' '$PLUGIN/skills/distill/SKILL.md'" "SKILL.md references SPINE.md"
assert_true "grep -q 'invoke_subagent' '$PLUGIN/skills/distill/SKILL.md'" "SKILL.md references subagent invocation"
assert_true "grep -q '.needs-migration' '$PLUGIN/skills/distill/SKILL.md'" "SKILL.md gates on pending migration"
assert_true "grep -q 'idle <ISO_TIMESTAMP>' '$PLUGIN/skills/distill/SKILL.md'" "SKILL.md resets .status on spawn failure"

# Test 3: rules sit at the DISCOVERED path and defer to the canonical monitor
assert_true "[[ -f '$PLUGIN/rules/AGENTS.md' ]]" "plugins/aura-distill/rules/AGENTS.md exists (discovery path)"
assert_true "grep -q 'SPINE.md' '$PLUGIN/rules/AGENTS.md'" "rules/AGENTS.md references SPINE.md"
assert_true "grep -q 'distill-monitor.md' '$PLUGIN/rules/AGENTS.md'" "rules/AGENTS.md defers to the canonical monitor"
assert_true "grep -q '.needs-migration' '$PLUGIN/rules/AGENTS.md'" "rules/AGENTS.md carries the migration gate"
assert_true "grep -q '\[NON-NEGOTIABLE\]' '$PLUGIN/rules/AGENTS.md'" "rules/AGENTS.md contains cognitive markers"

# Test 4: no stale duplicates outside the plugin (single canonical location)
assert_true "[[ ! -d '$REPO_ROOT/skills' ]]" "no root-level skills/ duplicate"
assert_true "[[ ! -f '$REPO_ROOT/rules/distill-agy.md' ]]" "no root-level rules/distill-agy.md duplicate"

# Test 5: bash Time Index twin exists (behavior covered by run-parity-test.sh)
assert_true "[[ -f '$REPO_ROOT/bin/distill-recent-agy.sh' ]]" "bin/distill-recent-agy.sh exists"

echo ""
echo "Summary: $pass_count passed, $fail_count failed."
if [[ $fail_count -gt 0 ]]; then exit 1; fi
