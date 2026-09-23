#!/usr/bin/env bash
# Deterministic test for run-clean-review.sh: a scratch clone, a fake PR ref and a stub `claude`.
# No network, no API calls, no real profile.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
runner="$here/run-clean-review.sh"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
pass=0; fail=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1"; fail=$((fail+1)); }

# Scratch "origin" with a PR head ref, and a clone of it.
git init -q "$t/origin"; git -C "$t/origin" config user.email t@t; git -C "$t/origin" config user.name t
cp "$here/../../REVIEW-PROTOCOL.md" "$t/origin/"
git -C "$t/origin" add -A; git -C "$t/origin" commit -q -m base
git -C "$t/origin" update-ref refs/pull/7/head HEAD
git clone -q "$t/origin" "$t/clone"

# Stub claude: records its args and env, prints a fake review, exits with $STUB_EXIT.
mkdir -p "$t/bin"
cat > "$t/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_ARGS"
echo "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR" >> "$STUB_ARGS"
echo "#### Verdict"; echo "APPROVE (stub)"
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$t/bin/claude"
mkdir -p "$t/profile"

run(){ ( cd "$t/clone" && CLAUDE_BIN="$t/bin/claude" REVIEWER_PROFILE="$t/profile" REVIEW_OUT_DIR="$t/out" \
         STUB_ARGS="$t/args" STUB_EXIT="${1:-0}" bash "$runner" 7 claude-test-model ) ; }

out="$(run 0 2>"$t/err")" && ok "exit 0 on success" || no "exit 0 on success"
grep -q 'APPROVE (stub)' <<<"$out" && ok "review printed on stdout" || no "review printed on stdout"
ls "$t/out"/review-7-*.md >/dev/null 2>&1 && ok "review kept in REVIEW_OUT_DIR" || no "review kept in REVIEW_OUT_DIR"
grep -q 'You are reviewing PR #7' "$t/args" && ok "verbatim template with PR number" || no "verbatim template with PR number"
grep -q '{PR_NUMBER}' "$t/args" && no "no unfilled placeholder" || ok "no unfilled placeholder"
grep -qx -- '--strict-mcp-config' "$t/args" && ok "MCP servers blocked" || no "MCP servers blocked"
grep -q 'autoMemoryEnabled":false' "$t/args" && ok "auto-memory off" || no "auto-memory off"
grep -qx 'Bash(git push:\*)' "$t/args" && grep -qx 'Bash(gh pr merge:\*)' "$t/args" && ok "push and merge disallowed" || no "push and merge disallowed"
grep -qx "CLAUDE_CONFIG_DIR=$t/profile" "$t/args" && ok "reviewer profile used" || no "reviewer profile used"
[ -z "$(git -C "$t/clone" branch --list 'review/*')" ] && ok "no branch leaked" || no "no branch leaked"
[ "$(git -C "$t/clone" worktree list | wc -l | tr -d ' ')" = 1 ] && ok "worktree removed" || no "worktree removed"
grep -q "Reviewed head: $(git -C "$t/origin" rev-parse HEAD)" <<<"$out" && ok "reviewed head recorded" || no "reviewed head recorded"
grep -qx 'Bash(./test-sandbox.sh:\*)' "$t/args" && ok "live harness disallowed" || no "live harness disallowed"

set +e; out="$(run 3 2>/dev/null)"; st=$?; set -e
[ "$st" = 3 ] && ok "reviewer failure status propagated" || no "reviewer failure status propagated ($st)"
grep -q 'APPROVE (stub)' <<<"$out" && ok "output kept on failure" || no "output kept on failure"

set +e; ( cd "$t/clone" && CLAUDE_BIN="$t/bin/claude" REVIEWER_PROFILE="$t/profile" bash "$runner" 7 ) >/dev/null 2>&1; st=$?; set -e
[ "$st" = 2 ] && ok "model argument required" || no "model argument required ($st)"
mkdir -p "$t/profile/rules"; : > "$t/profile/rules/distill.md"
set +e; ( cd "$t/clone" && CLAUDE_BIN="$t/bin/claude" REVIEWER_PROFILE="$t/profile" bash "$runner" 7 m ) >/dev/null 2>&1; st=$?; set -e
[ "$st" = 2 ] && ok "profile with aura-distill refused" || no "profile with aura-distill refused ($st)"

echo; echo "run-clean-review: $pass passed, $fail failed"; [ "$fail" = 0 ]
