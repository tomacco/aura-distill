#!/usr/bin/env bash
# Run one independent PR review in a clean reviewer environment (REVIEW-PROTOCOL.md rule 9).
#
# The reviewer runs headless in its own Claude Code profile, so it never loads the
# maintainer's memory (rules/distill.md, CLAUDE.md, a knowledge store) and never sees the
# author's context. It gets a fresh git worktree of the PR head and no MCP servers.
#
# Usage: tests/review/run-clean-review.sh <pr-number> [model]
#   model defaults to claude-fable-5-1; pick one that differs from the author's (rule 7).
#
# Needs: a reviewer profile that has logged in once and never ran the aura-distill installer:
#   CLAUDE_CONFIG_DIR=~/.claude-reviewer claude   # then /login, then quit
# Override the profile with REVIEWER_PROFILE=/path.
#
# Output: the review on stdout and in $OUT_DIR/review-<pr>-<utc>.md (OUT_DIR defaults to a temp dir).
# Nothing is posted: the authoring agent posts the review (rule 8).
set -euo pipefail

pr="${1:?usage: run-clean-review.sh <pr-number> [model]}"
model="${2:-claude-fable-5-1}"
case "$pr" in (*[!0-9]*|'') echo "PR number must be digits" >&2; exit 2;; esac
profile="${REVIEWER_PROFILE:-$HOME/.claude-reviewer}"
repo="${REVIEW_REPO:-tomacco/aura-distill}"

if [ ! -d "$profile" ]; then
  echo "No reviewer profile at $profile. Create it once: CLAUDE_CONFIG_DIR=$profile claude, then /login." >&2
  exit 2
fi
# A profile that ran the installer would load distill memory, which defeats the point.
if [ -e "$profile/rules/distill.md" ] || grep -qs 'aura-distill' "$profile/CLAUDE.md"; then
  echo "Reviewer profile $profile has aura-distill installed; use a profile that never ran the installer." >&2
  exit 2
fi

root="$(git rev-parse --show-toplevel)"
template="$root/REVIEW-PROTOCOL.md"
work="$(mktemp -d)"
trap 'git -C "$root" worktree remove --force "$work/wt" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

git -C "$root" fetch -q origin "pull/$pr/head:review/pr-$pr-$$"
git -C "$root" worktree add -q "$work/wt" "review/pr-$pr-$$"
git -C "$root" branch -q -D "review/pr-$pr-$$" >/dev/null 2>&1 || true

# The prompt is the verbatim template from REVIEW-PROTOCOL.md with only the PR number filled in,
# plus the repository name (the reviewer's worktree has no gh default repo).
prompt="$(awk '/^## Review prompt template/{f=1} f' "$template" | awk '/^```$/{c++; next} c==1' | sed "s/{PR_NUMBER}/$pr/g")"
prompt="$prompt

(Repository: $repo — pass -R $repo to gh.)"

out_dir="${OUT_DIR:-$work/out}"; mkdir -p "$out_dir"
out="$out_dir/review-$pr-$(date -u +%Y%m%dT%H%M%SZ).md"

( cd "$work/wt" && CLAUDE_CONFIG_DIR="$profile" claude -p "$prompt" \
    --model "$model" \
    --strict-mcp-config \
    --allowedTools "Read" "Grep" "Glob" "Bash" \
  ) > "$out"

cat "$out"
echo "Reviewer model: $model · profile: $profile · review saved to $out" >&2
