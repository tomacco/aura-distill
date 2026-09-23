#!/usr/bin/env bash
# Reference behavior for the software-major consent boundary decided in
# docs/adr/0001-legacy-updater-compatibility.md. NOT shipped; it exists so the
# non-interactive rule has an executable specification the runner can assert:
#
#   - consent is enforced BEFORE any payload download, install, execution or
#     store migration (the only earlier network read is the manifest/guide);
#   - consent requires a terminal AND the typed phrase "adopt <version>";
#   - no terminal, piped input, empty input, timeout or any other answer means
#     "stay on files-only": nothing is written, exit code 2.
#
# Usage: consent-gate.sh <major-version> <requirements-text> <guide-url> <store-dir>
set -u
MAJOR=${1:?major version}
REQUIREMENTS=${2:?requirements}
GUIDE=${3:?guide url}
STORE=${4:?store dir}

notice() {
  cat <<EOF
aura-distill software edition v${MAJOR} is a major change from files-only.
Installing it will: ${REQUIREMENTS}.
Read ${GUIDE} before continuing. Your files-only installation stays supported
and is not changed unless you consent here.
EOF
}

notice

# Consent boundary. Everything after this block is a side effect.
if [ ! -t 0 ] || [ ! -t 1 ]; then
  echo "No interactive terminal: consent cannot be given here. Kept files-only. Nothing was installed or changed."
  exit 2
fi
printf 'Type "adopt %s" to continue, or press Enter to keep files-only: ' "$MAJOR"
answer=""
if ! read -r -t 300 answer; then answer=""; fi
if [ "$answer" != "adopt $MAJOR" ]; then
  echo "Kept files-only. Nothing was installed or changed."
  exit 2
fi

# Consent recorded before the first side effect, so a later step can prove it.
mkdir -p "$STORE"
printf 'consented %s %s\n' "$MAJOR" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STORE/.major-consent"
echo "Consent recorded for v${MAJOR}. Download/install/migration may proceed."
exit 0
