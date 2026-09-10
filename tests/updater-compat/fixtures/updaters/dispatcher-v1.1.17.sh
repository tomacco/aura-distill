# Captured shipped updater instructions: distill.md "Update procedure (when accepted)"
# Source: origin/main f257a4e (VERSION 1.1.17, 2026-08-02). The mkdir line was added at
# 87a6b64 (VERSION 1.1.14). Same three fixed main URLs as every version since 1.0.0.
# Runner rewrites: raw.githubusercontent.com -> local fixture endpoint; NEW_VERSION -> fetched VERSION;
# {DISTILL_DIR} -> sandbox store path. Everything below this line is what shipped.
curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/distill.md -o ~/.claude/commands/distill.md
curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/distill-process.md -o {DISTILL_DIR}/distill-process.md
curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/distill-monitor.md -o {DISTILL_DIR}/distill-monitor.md
mkdir -p {DISTILL_DIR}/data {DISTILL_DIR}/inbox
echo "NEW_VERSION" > {DISTILL_DIR}/.version
