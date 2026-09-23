# Captured shipped updater instructions: distill.md "Update procedure (when accepted)"
# Source: tag v1.0.0 = commit 7dcbd7f (2026-05-17; the VERSION file reads 1.0.1 at that commit).
# The identical block first shipped at 0292f23 (rename claude-distill -> aura-distill, VERSION 1.0.0).
# {DISTILL_DIR} was resolved by install.sh at install time (~/.claude/distill for 1.0.x-1.1.9,
# ~/.aura-distill from 1.1.10). The runner resolves it the same way.
# Runner rewrites: raw.githubusercontent.com -> local fixture endpoint; NEW_VERSION -> fetched VERSION;
# {DISTILL_DIR} -> sandbox store path. Everything below this line is what shipped.
curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/distill.md -o ~/.claude/commands/distill.md
curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/distill-process.md -o {DISTILL_DIR}/distill-process.md
curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/distill-monitor.md -o {DISTILL_DIR}/distill-monitor.md
echo "NEW_VERSION" > {DISTILL_DIR}/.version
