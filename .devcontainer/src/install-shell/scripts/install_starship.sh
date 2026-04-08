#!/usr/bin/env bash
# install_starship.sh — Install the Starship cross-shell prompt.
#
# Downloads and installs Starship via the official installer script.
set -euo pipefail

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------
# shellcheck source=helpers.sh
_SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$_SCRIPTS_DIR/helpers.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
__usage__() {
  cat >&2 <<'EOF'
Usage: install_starship.sh [OPTIONS]

Options:
  --bin_dir <string>   Installation directory for the binary (default: /usr/local/bin)
  --debug              Enable debug output (set -x)
  -h, --help           Show this help
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
if [ "$#" -gt 0 ]; then
  BIN_DIR=""
  DEBUG=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --bin_dir) shift; BIN_DIR="$1"; shift;;
      --debug) DEBUG=true; shift;;
      --help|-h) __usage__;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *) echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
    esac
  done
fi

: "${BIN_DIR:=/usr/local/bin}"
: "${DEBUG:=false}"

[[ "$DEBUG" == true ]] && set -x

# Skip if already installed.
if [ -x "${BIN_DIR}/starship" ]; then
  echo "ℹ️  Starship already installed at '${BIN_DIR}/starship' — skipping." >&2
  exit 0
fi

echo "ℹ️  Installing Starship to '${BIN_DIR}'..." >&2

# ---------------------------------------------------------------------------
# Download and run the official installer
# ---------------------------------------------------------------------------
_INSTALLER_SCRIPT="$(mktemp)"
trap 'rm -f "$_INSTALLER_SCRIPT"' EXIT

fetch_with_retry 3 curl -fsSL "https://starship.rs/install.sh" -o "$_INSTALLER_SCRIPT"
chmod +x "$_INSTALLER_SCRIPT"

# The official installer supports --yes (non-interactive) and --bin-dir.
sh "$_INSTALLER_SCRIPT" --yes --bin-dir "$BIN_DIR" >&2

if [ -x "${BIN_DIR}/starship" ]; then
  echo "✅ Starship installed to '${BIN_DIR}/starship'." >&2
else
  echo "⛔ Starship installation failed." >&2
  exit 1
fi
