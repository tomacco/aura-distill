# Captured shipped installer fetch lines: install.sh at tag v1.0.0 (lines 13, 214, 218, 222, 244).
# This is the installer the Homebrew formula still runs (homebrew/Formula/aura-distill.rb pins the
# v1.0.0 tarball and execs its install.sh). REPO is hardcoded: no override, no local-path support,
# so a "pinned" Homebrew install fetches whatever main serves today.
# The runner sets CMD_DIR, DISTILL_DIR and RULES_DIR to sandbox paths and rewrites
# raw.githubusercontent.com -> local fixture endpoint. Everything below this line is what shipped.
REPO="https://raw.githubusercontent.com/tomacco/aura-distill/main"
curl -sL "$REPO/distill.md" | sed "s|{DISTILL_DIR}|$DISTILL_DIR|g" > "$CMD_DIR/distill.md"
curl -sL "$REPO/distill-process.md" | sed "s|{DISTILL_DIR}|$DISTILL_DIR|g" > "$DISTILL_DIR/distill-process.md"
curl -sL "$REPO/distill-monitor.md" | sed "s|{DISTILL_DIR}|$DISTILL_DIR|g" > "$DISTILL_DIR/distill-monitor.md"
curl -sL "$REPO/rules/distill.md" | sed "s|{DISTILL_DIR}|$DISTILL_DIR|g" > "$RULES_DIR/distill.md"
