# Captured shipped updater instructions: distill.md "Update procedure (when accepted)"
# Source: commit 476b093 "Redesign update flow: user-controlled, inside /distill" (2026-05-07)
# VERSION at that commit: 0.3.1. Oldest client that carries this exact curl block.
# Repo name at that time: tomacco/claude-distill (renamed 2026-05-17; raw URL still served, see ADR).
# The block is executed verbatim by the runner. The only rewrites the runner applies:
#   https://raw.githubusercontent.com -> the local fixture endpoint (never the network)
#   NEW_VERSION -> the fetched VERSION content (what the agent substitutes at step 3)
# Everything below this line is byte-for-byte what shipped.
curl -sL https://raw.githubusercontent.com/tomacco/claude-distill/main/distill.md -o ~/.claude/commands/distill.md
curl -sL https://raw.githubusercontent.com/tomacco/claude-distill/main/distill-process.md -o ~/.claude/distill/distill-process.md
curl -sL https://raw.githubusercontent.com/tomacco/claude-distill/main/distill-monitor.md -o ~/.claude/distill/distill-monitor.md
echo "NEW_VERSION" > ~/.claude/distill/.version
