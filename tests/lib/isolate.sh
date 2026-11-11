#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/real-profile-guard.sh"
# ═══════════════════════════════════════════════════════════════════════════════
# Test Isolation Protocol for aura-distill research
#
# Source this file, then call:
#   isolate_begin    — strip all personal context (backup everything)
#   isolate_end      — restore everything
#   isolate_run      — run Claude in the isolated environment
#
# Based on the validated protocol from distill-benchmark (2026-05-17).
#
# Usage:
#   source tests/lib/isolate.sh
#   isolate_begin
#   result=$(isolate_run "your prompt here" "optional system context" "optional knowledge dir")
#   isolate_end
# ═══════════════════════════════════════════════════════════════════════════════

REAL_CONFIG="${DISTILL_TEST_CONFIG:-${REAL_CONFIG:-$HOME/.claude}}"
CLAUDE_BIN="${CLAUDE_BIN:-node /opt/homebrew/opt/claude-code-npm/libexec/lib/node_modules/@anthropic-ai/claude-code/cli.js}"
SANDBOX_PROFILE='(version 1)(allow default)(deny file-read* (literal "/Library/Application Support/ClaudeCode/managed-settings.json"))'
RULES_SRC="${RULES_SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/rules/distill.md}"

# SAFETY: permanent backup location (NEVER modified by tests)
_PERMANENT_BACKUP="$HOME/.claude/backups/CLAUDE.md.latest"

# Pre-flight: ensure permanent backup exists before ANY test runs
if [ ! -f "$_PERMANENT_BACKUP" ]; then
    if [ -f "$HOME/.claude/CLAUDE.md" ] && [ "$(wc -l < "$HOME/.claude/CLAUDE.md")" -gt 5 ]; then
        mkdir -p "$HOME/.claude/backups"
        cp "$HOME/.claude/CLAUDE.md" "$_PERMANENT_BACKUP"
        echo "Created permanent CLAUDE.md backup ($(wc -l < "$_PERMANENT_BACKUP") lines)" >&2
    else
        echo "ERROR: No permanent CLAUDE.md backup exists and current file looks wrong." >&2
        echo "Refusing to run tests — this could destroy your config." >&2
        echo "Fix: cp ~/.claude/CLAUDE.md ~/.claude/backups/CLAUDE.md.latest" >&2
        return 1 2>/dev/null || exit 1
    fi
fi

# Backup locations — use PERSISTENT path (survives process death)
_ISO_BACKUP="$HOME/.claude/_isolation_backup"
_ISO_WORKSPACE=""
_ISO_ACTIVE=false

# Recovery: if isolation backup exists from a crashed run, restore first
if [ -d "$_ISO_BACKUP" ] && [ -f "$_ISO_BACKUP/global-claude-md" ]; then
    echo "WARNING: Recovering from crashed isolation. Restoring..." >&2
    cp "$_ISO_BACKUP/global-claude-md" "$HOME/.claude/CLAUDE.md" 2>/dev/null || true
    cp "$_ISO_BACKUP/personal-claude-md" "${REAL_CONFIG}/CLAUDE.md" 2>/dev/null || true
    [ -d "$HOME/.claude/_distill_isolation_bak" ] && mv "$HOME/.claude/_distill_isolation_bak" "$HOME/.claude/distill"
    [ -d "$HOME/.claude/_rules_isolation_bak" ] && mv "$HOME/.claude/_rules_isolation_bak" "$HOME/.claude/rules"
    [ -d "$HOME/.claude/_plugins_isolation_bak" ] && mv "$HOME/.claude/_plugins_isolation_bak" "$HOME/.claude/plugins"
    [ -d "${REAL_CONFIG}/_distill_isolation_bak" ] && mv "${REAL_CONFIG}/_distill_isolation_bak" "${REAL_CONFIG}/distill"
    [ -d "${REAL_CONFIG}/_rules_isolation_bak" ] && mv "${REAL_CONFIG}/_rules_isolation_bak" "${REAL_CONFIG}/rules"
    [ -d "${REAL_CONFIG}/_plugins_isolation_bak" ] && mv "${REAL_CONFIG}/_plugins_isolation_bak" "${REAL_CONFIG}/plugins"
    for settings_path in "$HOME/.claude/settings.json" "${REAL_CONFIG}/settings.json"; do
        bak_name=$(echo "$settings_path" | tr '/' '_')
        [ -f "$_ISO_BACKUP/$bak_name" ] && cp "$_ISO_BACKUP/$bak_name" "$settings_path"
    done 2>/dev/null
    rm -rf "$_ISO_BACKUP"
    echo "Recovery complete." >&2
elif [ -f "$HOME/.claude/CLAUDE.md" ] && [ "$(wc -l < "$HOME/.claude/CLAUDE.md" 2>/dev/null)" -lt 5 ]; then
    # CLAUDE.md looks like a test stub — restore from permanent backup
    echo "WARNING: CLAUDE.md looks like a test stub. Restoring from permanent backup..." >&2
    cp "$_PERMANENT_BACKUP" "$HOME/.claude/CLAUDE.md"
    echo "Restored from $_PERMANENT_BACKUP" >&2
fi

isolate_begin() {
    if [ "$_ISO_ACTIVE" = true ]; then
        echo "ERROR: isolate_begin called while isolation is active. Call isolate_end first." >&2
        return 1
    fi

    mkdir -p "$_ISO_BACKUP"
    _ISO_WORKSPACE=$(mktemp -d "/tmp/distill-test-workspace-XXXX")
    _ISO_ACTIVE=true

    # ── 1. Backup and blank ~/.claude/CLAUDE.md ──
    cp "$HOME/.claude/CLAUDE.md" "$_ISO_BACKUP/global-claude-md" 2>/dev/null || true
    echo "# Test session — isolated" > "$HOME/.claude/CLAUDE.md"

    # ── 2. Backup and blank $REAL_CONFIG/CLAUDE.md ──
    cp "$REAL_CONFIG/CLAUDE.md" "$_ISO_BACKUP/personal-claude-md" 2>/dev/null || true
    echo "# Test session — isolated" > "$REAL_CONFIG/CLAUDE.md" 2>/dev/null || true

    # ── 3. Hide ~/.claude/rules/ ──
    if [ -d "$HOME/.claude/rules" ] && [ ! -d "$HOME/.claude/_rules_isolation_bak" ]; then
        mv "$HOME/.claude/rules" "$HOME/.claude/_rules_isolation_bak"
    fi

    # ── 4. Hide $REAL_CONFIG/rules/ ──
    if [ -d "$REAL_CONFIG/rules" ] && [ ! -d "$REAL_CONFIG/_rules_isolation_bak" ]; then
        mv "$REAL_CONFIG/rules" "$REAL_CONFIG/_rules_isolation_bak"
    fi

    # ── 5. Hide ~/.claude/distill/ ──
    if [ -d "$HOME/.claude/distill" ] && [ ! -d "$HOME/.claude/_distill_isolation_bak" ]; then
        mv "$HOME/.claude/distill" "$HOME/.claude/_distill_isolation_bak"
    fi

    # ── 6. Hide $REAL_CONFIG/distill/ ──
    if [ -d "$REAL_CONFIG/distill" ] && [ ! -d "$REAL_CONFIG/_distill_isolation_bak" ]; then
        mv "$REAL_CONFIG/distill" "$REAL_CONFIG/_distill_isolation_bak"
    fi

    # ── 7. Hide ~/.claude/plugins/ ──
    if [ -d "$HOME/.claude/plugins" ] && [ ! -d "$HOME/.claude/_plugins_isolation_bak" ]; then
        mv "$HOME/.claude/plugins" "$HOME/.claude/_plugins_isolation_bak"
    fi

    # ── 8. Hide $REAL_CONFIG/plugins/ ──
    if [ -d "$REAL_CONFIG/plugins" ] && [ ! -d "$REAL_CONFIG/_plugins_isolation_bak" ]; then
        mv "$REAL_CONFIG/plugins" "$REAL_CONFIG/_plugins_isolation_bak"
    fi

    # ── 9. Strip settings.json (backup, remove customInstructions + enabledPlugins) ──
    for settings_path in "$HOME/.claude/settings.json" "$REAL_CONFIG/settings.json"; do
        if [ -f "$settings_path" ]; then
            local bak_name=$(echo "$settings_path" | tr '/' '_')
            cp "$settings_path" "$_ISO_BACKUP/$bak_name"
            # Remove customInstructions and enabledPlugins keys (crude but effective)
            sed -i '' '/"customInstructions"/d; /"enabledPlugins"/,/^  }/d' "$settings_path" 2>/dev/null || true
        fi
    done

    # ── 10. Create neutral workspace ──
    echo "# Neutral test workspace" > "$_ISO_WORKSPACE/README.md"

    # Ensure REAL_CONFIG/rules exists (empty) for test knowledge installation
    mkdir -p "$REAL_CONFIG/rules"
}

isolate_end() {
    if [ "$_ISO_ACTIVE" != true ]; then
        return 0
    fi

    # ── Restore CLAUDE.md files ──
    if [ -f "$_ISO_BACKUP/global-claude-md" ]; then
        cp "$_ISO_BACKUP/global-claude-md" "$HOME/.claude/CLAUDE.md"
    elif [ -f "$_PERMANENT_BACKUP" ]; then
        # Fallback: use permanent backup
        cp "$_PERMANENT_BACKUP" "$HOME/.claude/CLAUDE.md"
    fi
    [ -f "$_ISO_BACKUP/personal-claude-md" ] && cp "$_ISO_BACKUP/personal-claude-md" "$REAL_CONFIG/CLAUDE.md" 2>/dev/null

    # ── Restore rules/ ──
    rm -rf "$REAL_CONFIG/rules" 2>/dev/null
    [ -d "$HOME/.claude/_rules_isolation_bak" ] && mv "$HOME/.claude/_rules_isolation_bak" "$HOME/.claude/rules"
    [ -d "$REAL_CONFIG/_rules_isolation_bak" ] && mv "$REAL_CONFIG/_rules_isolation_bak" "$REAL_CONFIG/rules"

    # ── Restore distill/ ──
    [ -d "$HOME/.claude/_distill_isolation_bak" ] && mv "$HOME/.claude/_distill_isolation_bak" "$HOME/.claude/distill"
    [ -d "$REAL_CONFIG/_distill_isolation_bak" ] && mv "$REAL_CONFIG/_distill_isolation_bak" "$REAL_CONFIG/distill"

    # ── Restore plugins/ ──
    [ -d "$HOME/.claude/_plugins_isolation_bak" ] && mv "$HOME/.claude/_plugins_isolation_bak" "$HOME/.claude/plugins"
    [ -d "$REAL_CONFIG/_plugins_isolation_bak" ] && mv "$REAL_CONFIG/_plugins_isolation_bak" "$REAL_CONFIG/plugins"

    # ── Restore settings.json ──
    for settings_path in "$HOME/.claude/settings.json" "$REAL_CONFIG/settings.json"; do
        local bak_name=$(echo "$settings_path" | tr '/' '_')
        [ -f "$_ISO_BACKUP/$bak_name" ] && cp "$_ISO_BACKUP/$bak_name" "$settings_path"
    done

    # ── Cleanup ──
    rm -rf "$_ISO_BACKUP" "$_ISO_WORKSPACE" 2>/dev/null
    _ISO_ACTIVE=false
}

# Run Claude with isolation active
# Args: prompt [system_context] [knowledge_dir]
isolate_run() {
    local prompt="$1"
    local system_context="${2:-}"
    local knowledge_dir="${3:-}"
    local output_file=$(mktemp)
    local cmd_args="--dangerously-skip-permissions"

    # System prompt append
    local sys_file=""
    if [ -n "$system_context" ]; then
        sys_file=$(mktemp)
        echo "$system_context" > "$sys_file"
        cmd_args="$cmd_args --append-system-prompt-file $sys_file"
    fi

    # Install knowledge if provided
    if [ -n "$knowledge_dir" ] && [ -d "$knowledge_dir" ]; then
        local test_knowledge=$(mktemp -d)
        cp "$knowledge_dir"/* "$test_knowledge/" 2>/dev/null || true
        sed "s|~/.claude/distill|$test_knowledge|g; s|{DISTILL_DIR}|$test_knowledge|g" "$RULES_SRC" > "$REAL_CONFIG/rules/distill.md"
    fi

    # Run from neutral workspace
    (
        cd "$_ISO_WORKSPACE" && \
        CLAUDE_CONFIG_DIR="$REAL_CONFIG" \
        CLAUDE_CODE_USE_BEDROCK=0 \
        ANTHROPIC_DEFAULT_OPUS_MODEL= \
        ANTHROPIC_DEFAULT_SONNET_MODEL= \
        ANTHROPIC_DEFAULT_HAIKU_MODEL= \
        ANTHROPIC_MODEL= \
        AWS_PROFILE= AWS_ACCESS_KEY_ID= AWS_SECRET_ACCESS_KEY= \
        AWS_SESSION_TOKEN= AWS_DEFAULT_REGION= \
        AWS_SHARED_CREDENTIALS_FILE=/dev/null AWS_CONFIG_FILE=/dev/null \
        sandbox-exec -p "$SANDBOX_PROFILE" \
        $CLAUDE_BIN $cmd_args -p "$prompt" > "$output_file" 2>&1
    ) &
    local pid=$!
    (sleep 120 && kill "$pid" 2>/dev/null) & local wd=$!
    wait "$pid" 2>/dev/null || true
    kill "$wd" 2>/dev/null || true; wait "$wd" 2>/dev/null || true

    # Cleanup knowledge
    rm -rf "${test_knowledge:-}" "${sys_file:-}" 2>/dev/null
    # Clear rules installed for this run (next run gets fresh)
    rm -f "$REAL_CONFIG/rules/distill.md" 2>/dev/null

    cat "$output_file"
    rm -f "$output_file" 2>/dev/null
}

# Trap to ensure restoration even on script failure
trap 'isolate_end' EXIT
