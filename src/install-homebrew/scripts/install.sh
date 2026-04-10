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
  CASKS=""
  DEBUG=""
  FORMULAE=""
  LOGFILE=""
  TAPS=""
  UPDATE=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --casks)    shift; CASKS="$1";    echo "📩 Read argument 'casks': '${CASKS}'" >&2;       shift;;
      --debug)    shift; DEBUG="$1";    echo "📩 Read argument 'debug': '${DEBUG}'" >&2;       shift;;
      --formulae) shift; FORMULAE="$1"; echo "📩 Read argument 'formulae': '${FORMULAE}'" >&2; shift;;
      --logfile)  shift; LOGFILE="$1";  echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2;   shift;;
      --taps)     shift; TAPS="$1";     echo "📩 Read argument 'taps': '${TAPS}'" >&2;         shift;;
      --update)   shift; UPDATE="$1";   echo "📩 Read argument 'update': '${UPDATE}'" >&2;     shift;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *)   echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
    esac
  done
else
  echo "ℹ️ Script called with no arguments. Reading environment variables." >&2
  [ "${CASKS+defined}"    ] && echo "📩 Read argument 'casks': '${CASKS}'" >&2
  [ "${DEBUG+defined}"    ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${FORMULAE+defined}" ] && echo "📩 Read argument 'formulae': '${FORMULAE}'" >&2
  [ "${LOGFILE+defined}"  ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
  [ "${TAPS+defined}"     ] && echo "📩 Read argument 'taps': '${TAPS}'" >&2
  [ "${UPDATE+defined}"   ] && echo "📩 Read argument 'update': '${UPDATE}'" >&2
fi

[[ "$DEBUG" == true ]] && set -x

[ -z "${CASKS-}"    ] && { echo "ℹ️ Argument 'CASKS' set to default value ''." >&2;     CASKS=""; }
[ -z "${DEBUG-}"    ] && { echo "ℹ️ Argument 'DEBUG' set to default value 'false'." >&2; DEBUG=false; }
[ -z "${FORMULAE-}" ] && { echo "ℹ️ Argument 'FORMULAE' set to default value ''." >&2;  FORMULAE=""; }
[ -z "${LOGFILE-}"  ] && { echo "ℹ️ Argument 'LOGFILE' set to default value ''." >&2;   LOGFILE=""; }
[ -z "${TAPS-}"     ] && { echo "ℹ️ Argument 'TAPS' set to default value ''." >&2;      TAPS=""; }
[ -z "${UPDATE-}"   ] && { echo "ℹ️ Argument 'UPDATE' set to default value 'true'." >&2; UPDATE=true; }

echo "========================================" >&2
echo "  install-homebrew" >&2
echo "========================================" >&2

# ── Verify Homebrew is present ────────────────────────────────────────────────
if ! command -v brew > /dev/null 2>&1; then
    echo "⛔ brew not found. The bootstrap should have installed it." >&2
    exit 1
fi
echo "✅ Homebrew $(brew --version | head -1) is available." >&2

# ── Update ────────────────────────────────────────────────────────────────────
if [[ "$UPDATE" == true ]]; then
    echo "🔄 Running brew update." >&2
    brew update
    echo "✅ brew update complete." >&2
fi

# ── Add taps ─────────────────────────────────────────────────────────────────
if [[ -n "$TAPS" ]]; then
    echo "🔧 Adding taps." >&2
    IFS=',' read -ra _tap_list <<< "$TAPS"
    for _tap in "${_tap_list[@]}"; do
        _tap="${_tap// /}"
        [[ -z "$_tap" ]] && continue
        echo "  tap: $_tap" >&2
        brew tap "$_tap"
    done
    echo "✅ Taps added." >&2
fi

# ── Install formulae ──────────────────────────────────────────────────────────
if [[ -n "$FORMULAE" ]]; then
    echo "📲 Installing formulae." >&2
    IFS=',' read -ra _formula_list <<< "$FORMULAE"
    for _formula in "${_formula_list[@]}"; do
        _formula="${_formula// /}"
        [[ -z "$_formula" ]] && continue
        echo "  formula: $_formula" >&2
        brew install "$_formula"
    done
    echo "✅ Formulae installed." >&2
fi

# ── Install casks ─────────────────────────────────────────────────────────────
if [[ -n "$CASKS" ]]; then
    echo "📲 Installing casks." >&2
    IFS=',' read -ra _cask_list <<< "$CASKS"
    for _cask in "${_cask_list[@]}"; do
        _cask="${_cask// /}"
        [[ -z "$_cask" ]] && continue
        echo "  cask: $_cask" >&2
        brew install --cask "$_cask"
    done
    echo "✅ Casks installed." >&2
fi

echo "↩️ Script exit: Homebrew Installation Devcontainer Feature Installer" >&2
