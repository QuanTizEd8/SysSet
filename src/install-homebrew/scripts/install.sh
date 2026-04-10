#!/usr/bin/env bash
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$(cd "$_SELF_DIR/.." && pwd)"

# ospkg.sh is not used here (brew IS the package manager on macOS), but
# logging.sh is sourced for log-to-file support.
. "$_SELF_DIR/_lib/logging.sh"
logging::setup
echo "↪️ Script entry: Homebrew Installation Devcontainer Feature Installer" >&2
trap 'logging::cleanup' EXIT

# ── Argument parsing (dual-mode: env vars or CLI flags) ───────────────────────
if [[ "$#" -gt 0 ]]; then
  DEBUG=""
  LOGFILE=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --debug)   shift; DEBUG="$1";   echo "📩 Read argument 'debug': '${DEBUG}'" >&2;   shift;;
      --logfile) shift; LOGFILE="$1"; echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2; shift;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *)   echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
    esac
  done
else
  echo "ℹ️ Script called with no arguments. Reading environment variables." >&2
  [ "${DEBUG+defined}"   ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
fi

[[ "$DEBUG" == true ]] && set -x

[ -z "${DEBUG-}"   ] && { echo "ℹ️ Argument 'DEBUG' set to default value 'false'." >&2; DEBUG=false; }
[ -z "${LOGFILE-}" ] && { echo "ℹ️ Argument 'LOGFILE' set to default value ''." >&2;   LOGFILE=""; }

echo "========================================" >&2
echo "  install-homebrew" >&2
echo "========================================" >&2

# ── Verify Homebrew is present ────────────────────────────────────────────────
if ! command -v brew > /dev/null 2>&1; then
    echo "⛔ brew not found. The bootstrap should have installed it." >&2
    exit 1
fi
echo "✅ Homebrew $(brew --version | head -1) is available." >&2

echo "↩️ Script exit: Homebrew Installation Devcontainer Feature Installer" >&2
