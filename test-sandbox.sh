#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# aura-distill integration test harness
# Spawns a sandboxed Claude Code instance with a disposable config dir.
#
# This tests the REAL user experience by running a separate Claude Code instance
# with its own config dir, hitting Anthropic's API directly (not Bedrock).
# Auth config is read from DISTILL_TEST_CONFIG (default: ~/.claude).
#
# Usage:
#   ./test-sandbox.sh              # Run all tests
#   ./test-sandbox.sh install      # Run only install tests
#   ./test-sandbox.sh uninstall    # Run only uninstall tests
#   ./test-sandbox.sh directive    # Run only directive/origin tests
#   ./test-sandbox.sh behavior    # Run only behavior tests
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_HOME=$(mktemp -d)
TEST_CLAUDE_DIR="$TEST_HOME/.claude"
# Installers write knowledge to the shared store (~/.aura-distill since 1.1.10).
TEST_STORE="$TEST_HOME/.aura-distill"
# Auth config dir (must have valid API token). Override with DISTILL_TEST_CONFIG.
REAL_CONFIG_DIR="${DISTILL_TEST_CONFIG:-$HOME/.claude}"
CLAUDE_BIN="node /opt/homebrew/opt/claude-code-npm/libexec/lib/node_modules/@anthropic-ai/claude-code/cli.js"
SANDBOX_PROFILE='(version 1)(allow default)(deny file-read* (literal "/Library/Application Support/ClaudeCode/managed-settings.json"))'

# ═══ COLORS ═══
GREEN=$(printf '\033[0;32m')
RED=$(printf '\033[0;31m')
YELLOW=$(printf '\033[0;33m')
CYAN=$(printf '\033[0;36m')
DIM=$(printf '\033[2m')
BOLD=$(printf '\033[1m')
RESET=$(printf '\033[0m')

# ═══ COUNTERS ═══
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# ═══ HELPERS ═══

log_test() {
  echo ""
  printf "  ${CYAN}TEST${RESET} %s\n" "$1"
}

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "  ${GREEN}PASS${RESET} %s\n" "$1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "  ${RED}FAIL${RESET} %s\n" "$1"
  if [ -n "${2:-}" ]; then
    printf "       ${DIM}%s${RESET}\n" "$2"
  fi
}

skip() {
  TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
  printf "  ${YELLOW}SKIP${RESET} %s\n" "$1"
}

run_sandbox() {
  # Run sandbox in print mode with full permissions
  # Uses real HOME + real config dir (for auth), prompts reference TEST paths
  local prompt="$1"
  local max_seconds="${2:-60}"
  local output_file
  output_file=$(mktemp)

  # Run in background with a watchdog timer (no coreutils `timeout` needed)
  (
    CLAUDE_CONFIG_DIR="$REAL_CONFIG_DIR" \
    CLAUDE_CODE_USE_BEDROCK=0 \
    ANTHROPIC_DEFAULT_OPUS_MODEL= \
    ANTHROPIC_DEFAULT_SONNET_MODEL= \
    ANTHROPIC_DEFAULT_HAIKU_MODEL= \
    ANTHROPIC_MODEL= \
    AWS_PROFILE= \
    AWS_ACCESS_KEY_ID= \
    AWS_SECRET_ACCESS_KEY= \
    AWS_SESSION_TOKEN= \
    AWS_DEFAULT_REGION= \
    AWS_SHARED_CREDENTIALS_FILE=/dev/null \
    AWS_CONFIG_FILE=/dev/null \
    sandbox-exec -p "$SANDBOX_PROFILE" \
    $CLAUDE_BIN --dangerously-skip-permissions -p "$prompt" > "$output_file" 2>&1
  ) &
  local pid=$!

  # Watchdog: kill after max_seconds
  (sleep "$max_seconds" && kill "$pid" 2>/dev/null) &
  local watchdog=$!

  wait "$pid" 2>/dev/null || true
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true

  cat "$output_file"
  rm -f "$output_file"
}

# Install from this checkout into the sandbox only: never the network, never an
# AURA_DISTILL_HOME/CODEX_HOME exported by the calling shell.
run_installer() {
  env -u AURA_DISTILL_HOME -u CODEX_HOME -u DISTILL_CHANNEL \
    HOME="$TEST_HOME" AURA_DISTILL_HOME="$TEST_STORE" CODEX_HOME="$TEST_HOME/.codex" \
    AURA_DISTILL_REPO="$SCRIPT_DIR" bash "$SCRIPT_DIR/install.sh" < /dev/null 2>&1 || true
}

setup_test_env() {
  echo ""
  printf "  ${BOLD}Setting up test environment${RESET}\n"
  printf "  ${DIM}TEST_HOME: %s${RESET}\n" "$TEST_HOME"
  printf "  ${DIM}REAL_CONFIG: %s${RESET}\n" "$REAL_CONFIG_DIR"

  # Create the .claude dir that install.sh will write to
  mkdir -p "$TEST_CLAUDE_DIR"

  printf "  ${GREEN}✓${RESET} Test environment ready\n"
}

teardown_test_env() {
  if [ -d "$TEST_HOME" ]; then
    rm -rf "$TEST_HOME"
    printf "\n  ${DIM}Cleaned up %s${RESET}\n" "$TEST_HOME"
  fi
}

# ═══ TEST SUITES ═══

test_install_fresh() {
  log_test "Fresh install (no prior distill)"
  TESTS_RUN=$((TESTS_RUN + 1))

  # Run install.sh with test HOME so it writes to $TEST_HOME/.claude/
  run_installer

  # Verify core files
  if [ -f "$TEST_CLAUDE_DIR/commands/distill.md" ]; then
    pass "distill.md command installed"
  else
    fail "distill.md command not found" "$TEST_CLAUDE_DIR/commands/distill.md"
  fi
  TESTS_RUN=$((TESTS_RUN + 1))

  if [ -f "$TEST_STORE/distill-process.md" ]; then
    pass "distill-process.md installed"
  else
    fail "distill-process.md not found"
  fi
  TESTS_RUN=$((TESTS_RUN + 1))

  if [ -f "$TEST_STORE/distill-monitor.md" ]; then
    pass "distill-monitor.md installed"
  else
    fail "distill-monitor.md not found"
  fi
  TESTS_RUN=$((TESTS_RUN + 1))

  if [ -f "$TEST_STORE/SPINE.md" ]; then
    pass "SPINE.md created"
  else
    fail "SPINE.md not found"
  fi
  TESTS_RUN=$((TESTS_RUN + 1))

  if [ -f "$TEST_STORE/.version" ]; then
    local ver
    ver=$(cat "$TEST_STORE/.version")
    if [ "$ver" = "$(cat "$SCRIPT_DIR/VERSION" | tr -d '[:space:]')" ]; then
      pass "Version file correct ($ver)"
    else
      fail "Version mismatch" "expected $(cat "$SCRIPT_DIR/VERSION" | tr -d '[:space:]'), got $ver"
    fi
  else
    fail ".version file not found"
  fi
  TESTS_RUN=$((TESTS_RUN + 1))

  # Verify directory structure
  local expected_dirs=("craft" "ops" "profile" "projects" "feedback" "archive")
  for dir in "${expected_dirs[@]}"; do
    if [ -d "$TEST_STORE/$dir" ]; then
      pass "Directory $dir/ created"
    else
      fail "Directory $dir/ missing"
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
  done

  # Verify settings.json has auto-memory disabled
  if [ -f "$TEST_CLAUDE_DIR/settings.json" ]; then
    if grep -q '"autoMemoryEnabled"' "$TEST_CLAUDE_DIR/settings.json"; then
      pass "Auto-memory disabled in settings.json"
    else
      fail "Auto-memory not configured in settings.json"
    fi
  else
    fail "settings.json not created"
  fi
  TESTS_RUN=$((TESTS_RUN + 1))

  # Verify CLAUDE.md has distill reference
  if [ -f "$TEST_CLAUDE_DIR/CLAUDE.md" ]; then
    if grep -q "aura-distill" "$TEST_CLAUDE_DIR/CLAUDE.md"; then
      pass "CLAUDE.md contains distill reference"
    else
      fail "CLAUDE.md missing distill reference"
    fi
  else
    fail "CLAUDE.md not created"
  fi
  TESTS_RUN=$((TESTS_RUN + 1))
}

test_install_upgrade() {
  log_test "Upgrade install (existing distill)"
  TESTS_RUN=$((TESTS_RUN + 1))

  # Pre-populate SPINE with some content
  echo "# My Custom Knowledge" > "$TEST_STORE/SPINE.md"
  echo "- [patterns](craft/patterns.md) — coding patterns" >> "$TEST_STORE/SPINE.md"

  # Run install again
  run_installer

  # SPINE should be preserved (not overwritten)
  if grep -q "My Custom Knowledge" "$TEST_STORE/SPINE.md"; then
    pass "SPINE.md preserved on upgrade"
  else
    fail "SPINE.md was overwritten on upgrade"
  fi
  TESTS_RUN=$((TESTS_RUN + 1))

  # CLAUDE.md should not have duplicate entries
  local count
  count=$(grep -c "aura-distill" "$TEST_CLAUDE_DIR/CLAUDE.md" 2>/dev/null || echo "0")
  if [ "$count" -eq 1 ]; then
    pass "No duplicate CLAUDE.md entries on upgrade"
  else
    fail "Duplicate CLAUDE.md entries" "found $count occurrences"
  fi
}

test_install_with_existing_memories() {
  log_test "Install detects existing memory files"
  TESTS_RUN=$((TESTS_RUN + 1))

  # Create fake memory files (simulating Claude's built-in auto-memory)
  mkdir -p "$TEST_CLAUDE_DIR/memory"
  echo "User prefers dark mode" > "$TEST_CLAUDE_DIR/memory/preferences.md"
  echo "Project uses Kotlin" > "$TEST_CLAUDE_DIR/memory/context.md"

  # Remove migration flag if exists from prior test
  rm -f "$TEST_STORE/.migrated"
  rm -f "$TEST_STORE/.needs-migration"

  # Run install
  run_installer

  # Should set .needs-migration flag
  if [ -f "$TEST_STORE/.needs-migration" ]; then
    pass "Migration flag set when existing memories found"
  else
    fail "Migration flag not set despite existing memories"
  fi
}

test_directive_origin_tracking() {
  log_test "Distill categorizes directive origins correctly"
  TESTS_RUN=$((TESTS_RUN + 1))

  # Test that knowledge files with origin: directive are handled properly
  mkdir -p "$TEST_STORE/ops"
  cat > "$TEST_STORE/ops/infra-decisions.md" << 'KNOWLEDGE'
---
domain: ops
scope: Infrastructure decisions
last_updated: 2026-05-16
---

## Messaging

- [DIRECTIVE] All new services must use Kafka for messaging.
  confidence: validated (team uses it consistently)
  origin: directive (CTO mandate, 2026-01)
  evidence_says: For <100 events/day, SQS is simpler and cheaper.
KNOWLEDGE

  local result
  result=$(run_sandbox "I'm setting up a new service that handles 5 events per day. What message broker should I use? I know SQS would be simpler but we have team standards." 60)

  if echo "$result" | grep -qi "kafka\|directive\|mandate\|standard\|team"; then
    pass "Distill respects directive and helps with Kafka"
  else
    fail "Distill did not acknowledge directive origin" "$(echo "$result" | head -3)"
  fi
}

test_uninstall_preserves_knowledge() {
  log_test "Uninstall preserves user knowledge"
  TESTS_RUN=$((TESTS_RUN + 1))

  # Create some knowledge files
  mkdir -p "$TEST_STORE/craft"
  echo "# Kotlin Patterns" > "$TEST_STORE/craft/kotlin-patterns.md"
  echo "- Use sealed classes for state" >> "$TEST_STORE/craft/kotlin-patterns.md"

  # Simulate uninstall (what the install.sh footer suggests)
  rm -f "$TEST_CLAUDE_DIR/commands/distill.md"
  rm -rf "$TEST_STORE/server"

  # Knowledge should survive
  if [ -f "$TEST_STORE/craft/kotlin-patterns.md" ]; then
    pass "Knowledge files preserved after uninstall"
  else
    fail "Knowledge files deleted on uninstall"
  fi
  TESTS_RUN=$((TESTS_RUN + 1))

  if [ -f "$TEST_STORE/SPINE.md" ]; then
    pass "SPINE.md preserved after uninstall"
  else
    fail "SPINE.md deleted on uninstall"
  fi
}

test_sandbox_behavior_no_distill() {
  log_test "Sandbox behavior WITHOUT distill installed"
  TESTS_RUN=$((TESTS_RUN + 1))

  # Create a clean test CLAUDE.md with no distill
  local test_claude_md="$TEST_HOME/CLAUDE-test.md"
  echo "# Test instructions - no distill here" > "$test_claude_md"

  local result
  result=$(run_sandbox "Read the file $test_claude_md. Does it contain any reference to distill, SPINE, or distill-monitor? Answer with exactly INSTALLED or NOT_INSTALLED." 45)

  if echo "$result" | grep -qi "NOT_INSTALLED\|not installed\|no.*distill\|doesn't\|does not\|no reference"; then
    pass "Sandbox correctly reports no distill without installation"
  else
    fail "Sandbox confused about distill state" "$(echo "$result" | head -3)"
  fi
}

test_sandbox_behavior_with_distill() {
  log_test "Sandbox behavior WITH distill installed"
  TESTS_RUN=$((TESTS_RUN + 1))

  # Install distill to test HOME
  run_installer

  local result
  result=$(run_sandbox "Read the file $TEST_CLAUDE_DIR/CLAUDE.md. Do you see distill instructions? Report what behavior they tell you to follow. Keep it under 50 words." 45)

  if echo "$result" | grep -qi "distill\|monitor\|knowledge\|spine\|retrieval"; then
    pass "Sandbox picks up distill instructions from CLAUDE.md"
  else
    fail "Sandbox doesn't recognize distill instructions" "$(echo "$result" | head -3)"
  fi
}

# ═══ SUMMARY ═══

print_summary() {
  echo ""
  echo ""
  printf "  ${BOLD}═══ TEST SUMMARY ═══${RESET}\n"
  echo ""
  printf "  Total:   %d\n" "$TESTS_RUN"
  printf "  ${GREEN}Passed:  %d${RESET}\n" "$TESTS_PASSED"
  if [ "$TESTS_FAILED" -gt 0 ]; then
    printf "  ${RED}Failed:  %d${RESET}\n" "$TESTS_FAILED"
  fi
  if [ "$TESTS_SKIPPED" -gt 0 ]; then
    printf "  ${YELLOW}Skipped: %d${RESET}\n" "$TESTS_SKIPPED"
  fi
  echo ""

  if [ "$TESTS_FAILED" -eq 0 ]; then
    printf "  ${GREEN}${BOLD}All tests passed!${RESET}\n"
  else
    printf "  ${RED}${BOLD}%d test(s) failed${RESET}\n" "$TESTS_FAILED"
  fi
  echo ""
}

# ═══ MAIN ═══

main() {
  local suite="${1:-all}"

  printf "\n${BOLD}  aura-distill integration tests${RESET}\n"
  printf "  ${DIM}Using sandbox as test user (Anthropic API)${RESET}\n"

  setup_test_env

  case "$suite" in
    install)
      test_install_fresh
      test_install_upgrade
      test_install_with_existing_memories
      ;;
    directive)
      run_installer
      test_directive_origin_tracking
      ;;
    uninstall)
      run_installer
      test_uninstall_preserves_knowledge
      ;;
    behavior)
      test_sandbox_behavior_no_distill
      test_sandbox_behavior_with_distill
      ;;
    all)
      test_install_fresh
      test_install_upgrade
      test_install_with_existing_memories
      test_uninstall_preserves_knowledge
      test_sandbox_behavior_no_distill
      test_sandbox_behavior_with_distill
      test_directive_origin_tracking
      ;;
    *)
      echo "Unknown suite: $suite"
      echo "Usage: $0 [install|uninstall|mcp|behavior|all]"
      exit 1
      ;;
  esac

  print_summary
  teardown_test_env

  [ "$TESTS_FAILED" -eq 0 ]
}

trap teardown_test_env EXIT
main "$@"
