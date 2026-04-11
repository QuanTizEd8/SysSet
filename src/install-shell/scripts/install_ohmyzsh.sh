#!/usr/bin/env bash
# install_ohmyzsh.sh — Install Oh My Zsh, custom themes, and custom plugins.
#
# Clones the Oh My Zsh repository into INSTALL_DIR, sets git metadata for
# `omz update`, scaffolds the ZSH_CUSTOM directory, and clones any requested
# custom theme and plugins from GitHub.
#
# This script is called by the main install-shell orchestrator.  It does NOT
# install packages, configure zshrc files, set default shells, or install
# fonts — those concerns are handled by the orchestrator and companion scripts.
set -euo pipefail

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------
_SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$_SCRIPTS_DIR/_lib/git.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
__usage__() {
  cat >&2 << 'EOF'
Usage: install_ohmyzsh.sh [OPTIONS]

Options:
  --branch <string>          Branch or tag to clone (default: master)
  --install_dir <string>     Oh My Zsh installation directory
  --zsh_custom_dir <string>  ZSH_CUSTOM directory (default: <install_dir>/custom)
  --theme <string>           Custom theme as owner/repo GitHub slug (optional)
  --plugins <string>         Comma-separated custom plugins as owner/repo slugs
  --debug                    Enable debug output (set -x)
  --logfile <string>         Log file path
  -h, --help                 Show this help
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
if [ "$#" -gt 0 ]; then
  BRANCH=""
  DEBUG=""
  INSTALL_DIR=""
  LOGFILE=""
  PLUGINS=""
  THEME=""
  ZSH_CUSTOM_DIR=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --branch)
        shift
        BRANCH="$1"
        shift
        ;;
      --debug)
        DEBUG=true
        shift
        ;;
      --install_dir)
        shift
        INSTALL_DIR="$1"
        shift
        ;;
      --logfile)
        shift
        LOGFILE="$1"
        shift
        ;;
      --plugins)
        shift
        PLUGINS="$1"
        shift
        ;;
      --theme)
        shift
        THEME="$1"
        shift
        ;;
      --zsh_custom_dir)
        shift
        ZSH_CUSTOM_DIR="$1"
        shift
        ;;
      --help | -h) __usage__ ;;
      --*)
        echo "⛔ Unknown option: '${1}'" >&2
        exit 1
        ;;
      *)
        echo "⛔ Unexpected argument: '${1}'" >&2
        exit 1
        ;;
    esac
  done
fi

: "${BRANCH:=master}"
: "${DEBUG:=false}"
: "${INSTALL_DIR:=/usr/local/share/oh-my-zsh}"
: "${LOGFILE:=}"
: "${PLUGINS:=}"
: "${THEME:=}"
: "${ZSH_CUSTOM_DIR:=${INSTALL_DIR}/custom}"

[[ "$DEBUG" == true ]] && set -x

echo "ℹ️  Installing Oh My Zsh to '${INSTALL_DIR}' (branch: ${BRANCH})..." >&2

# ---------------------------------------------------------------------------
# Clone Oh My Zsh
# ---------------------------------------------------------------------------
umask g-w,o-w
git::clone --url "https://github.com/ohmyzsh/ohmyzsh" --dir "$INSTALL_DIR" --branch "$BRANCH"

# Set oh-my-zsh update metadata so 'omz update' knows which remote/branch.
git -C "$INSTALL_DIR" config oh-my-zsh.remote origin
git -C "$INSTALL_DIR" config oh-my-zsh.branch "$BRANCH"

# ---------------------------------------------------------------------------
# Scaffold ZSH_CUSTOM directories
# ---------------------------------------------------------------------------
mkdir -p "${ZSH_CUSTOM_DIR}/themes" "${ZSH_CUSTOM_DIR}/plugins"

# ---------------------------------------------------------------------------
# Custom theme
# ---------------------------------------------------------------------------
if [ -n "${THEME}" ]; then
  _THEME_REPO_NAME="$(basename "$THEME")"
  git::clone \
    --url "https://github.com/${THEME}" \
    --dir "${ZSH_CUSTOM_DIR}/themes/${_THEME_REPO_NAME}"
  echo "ℹ️  Installed custom theme '${THEME}'." >&2
fi

# ---------------------------------------------------------------------------
# Custom plugins
# ---------------------------------------------------------------------------
if [ -n "${PLUGINS}" ]; then
  IFS=',' read -r -a _PLUGIN_SLUGS <<< "$PLUGINS"
  for _slug in "${_PLUGIN_SLUGS[@]}"; do
    _slug="${_slug// /}"
    [ -z "$_slug" ] && continue
    # Skip built-in plugin names (no '/'); only clone owner/repo slugs.
    if [[ "$_slug" != */* ]]; then
      echo "ℹ️  '${_slug}' is a built-in plugin — skipping clone." >&2
      continue
    fi
    _PLUGIN_NAME="$(basename "$_slug")"
    git::clone \
      --url "https://github.com/${_slug}" \
      --dir "${ZSH_CUSTOM_DIR}/plugins/${_PLUGIN_NAME}"
    echo "ℹ️  Installed custom plugin '${_slug}'." >&2
  done
fi

echo "✅ Oh My Zsh installation complete." >&2
