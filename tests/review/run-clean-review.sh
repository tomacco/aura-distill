#!/usr/bin/env bash
# Run one independent PR review in a clean reviewer environment (REVIEW-PROTOCOL.md rule 9).
#
# The reviewer runs headless in its own Claude Code profile, so it never loads the
# maintainer's memory (rules/distill.md, CLAUDE.md, a knowledge store) and never sees the
# author's context. It gets a fresh detached worktree of the PR head, no MCP servers,
# auto-memory off, and no tool that posts, pushes or merges.
#
# Usage: tests/review/run-clean-review.sh <pr-number> <model>
#   <model> is required and must differ from the author's model (rule 7),
#   e.g. claude-fable-5-1 or claude-sonnet-5.
#
# Needs: a reviewer profile that has logged in once and never ran the aura-distill installer:
#   CLAUDE_CONFIG_DIR=~/.claude-reviewer claude   # then /login, then quit
# Override the profile with REVIEWER_PROFILE=/path, the claude binary with CLAUDE_BIN.
#
# Output: the review on stdout, and a copy in $REVIEW_OUT_DIR (default: a new temp dir that is
# kept) whose path is printed on stderr. Nothing is posted: the authoring agent posts (rule 8).
# Exit status: the reviewer's.
set -euo pipefail

pr="${1:-}"; model="${2:-}"
if [ -z "$pr" ] || [ -z "$model" ]; then
  echo "usage: run-clean-review.sh <pr-number> <model>  (model must differ from the author's; rule 7)" >&2
  exit 2
fi
case "$pr" in (*[!0-9]*) echo "PR number must be digits" >&2; exit 2;; esac
profile="${REVIEWER_PROFILE:-$HOME/.claude-reviewer}"
repo="${REVIEW_REPO:-tomacco/aura-distill}"
claude_bin="${CLAUDE_BIN:-claude}"

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
cleanup(){ git -C "$root" worktree remove --force "$work/wt" >/dev/null 2>&1 || true; rm -rf "$work"; git -C "$root" worktree prune >/dev/null 2>&1 || true; }
trap cleanup EXIT
trap 'exit 130' INT TERM

# Detached worktree of the PR head: no local branch is created, so nothing leaks into the repo.
git -C "$root" fetch -q origin "pull/$pr/head"
git -C "$root" worktree add -q --detach "$work/wt" FETCH_HEAD
head_sha="$(git -C "$work/wt" rev-parse HEAD)"

# The prompt is the verbatim template from REVIEW-PROTOCOL.md with only the PR number filled in,
# plus the repository name (the reviewer's worktree has no gh default repo).
prompt="$(awk '/^## Review prompt template/{f=1} f' "$template" | awk '/^```$/{c++; next} c==1' | sed "s/{PR_NUMBER}/$pr/g")"
if [ -z "$prompt" ]; then echo "Could not extract the review template from $template" >&2; exit 2; fi
prompt="$prompt

(Repository: $repo — pass -R $repo to gh.)"

out_dir="${REVIEW_OUT_DIR:-$(mktemp -d)}"; mkdir -p "$out_dir"
out="$out_dir/review-$pr-$(date -u +%Y%m%dT%H%M%SZ).md"

status=0
( cd "$work/wt" && CLAUDE_CONFIG_DIR="$profile" "$claude_bin" -p "$prompt" \
    --model "$model" \
    --strict-mcp-config \
    --settings '{"autoMemoryEnabled":false}' \
    --allowedTools "Read" "Grep" "Glob" "Bash" \
    --disallowedTools "Bash(gh pr comment:*)" "Bash(gh pr review:*)" "Bash(gh pr merge:*)" \
      "Bash(gh pr edit:*)" "Bash(gh pr close:*)" "Bash(gh issue comment:*)" "Bash(gh api:*)" \
      "Bash(git push:*)" "Bash(./test-sandbox.sh:*)" "Bash(bash test-sandbox.sh:*)" "Bash(bash ./test-sandbox.sh:*)" \
  ) > "$out" || status=$?

cat "$out"
echo "Reviewed head: $head_sha" >> "$out"
echo "Reviewed head: $head_sha"
echo "Reviewer model: $model · profile: $profile · review saved to $out · exit $status" >&2
exit "$status"
