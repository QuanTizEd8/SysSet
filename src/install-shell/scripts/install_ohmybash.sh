#!/usr/bin/env bash
# install_ohmybash.sh — Install Oh My Bash, custom themes, and custom plugins.
#
# Mirrors install_ohmyzsh.sh for the bash counterpart.
# Clones the Oh My Bash repository into INSTALL_DIR, sets git metadata for
# `omb update`, scaffolds the OSH_CUSTOM directory, and clones any requested
# custom theme and plugins from GitHub.
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
Usage: install_ohmybash.sh [OPTIONS]

Options:
  --branch <string>          Branch or tag to clone (default: master)
  --install_dir <string>     Oh My Bash installation directory
  --osh_custom_dir <string>  OSH_CUSTOM directory (default: <install_dir>/custom)
  --theme <string>           Custom theme as owner/repo GitHub slug (optional)
  --plugins <string>         Comma-separated custom plugins as owner/repo slugs
  --debug                    Enable debug output (set -x)
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
  PLUGINS=""
  THEME=""
  OSH_CUSTOM_DIR=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --branch) shift; BRANCH="$1"; shift;;
      --debug) DEBUG=true; shift;;
      --install_dir) shift; INSTALL_DIR="$1"; shift;;
      --plugins) shift; PLUGINS="$1"; shift;;
      --theme) shift; THEME="$1"; shift;;
      --osh_custom_dir) shift; OSH_CUSTOM_DIR="$1"; shift;;
      --help|-h) __usage__;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *) echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
    esac
  done
fi

[ -z "${BRANCH-}" ]          && BRANCH="master"
[ -z "${DEBUG-}" ]            && DEBUG=false
[ -z "${INSTALL_DIR-}" ]      && INSTALL_DIR="/usr/local/share/oh-my-bash"
[ -z "${PLUGINS-}" ]          && PLUGINS=""
[ -z "${THEME-}" ]            && THEME=""
[ -z "${OSH_CUSTOM_DIR-}" ]   && OSH_CUSTOM_DIR="${INSTALL_DIR}/custom"

[[ "$DEBUG" == true ]] && set -x

echo "ℹ️  Installing Oh My Bash to '${INSTALL_DIR}' (branch: ${BRANCH})..." >&2

# ---------------------------------------------------------------------------
# Clone Oh My Bash
# ---------------------------------------------------------------------------
umask g-w,o-w
git_clone --url "https://github.com/ohmybash/oh-my-bash" --dir "$INSTALL_DIR" --branch "$BRANCH"

# Set update metadata so 'omb update' knows which remote/branch.
git -C "$INSTALL_DIR" config oh-my-bash.remote origin
git -C "$INSTALL_DIR" config oh-my-bash.branch "$BRANCH"

# ---------------------------------------------------------------------------
# Scaffold OSH_CUSTOM directories
# ---------------------------------------------------------------------------
mkdir -p "${OSH_CUSTOM_DIR}/themes" "${OSH_CUSTOM_DIR}/plugins"

# ---------------------------------------------------------------------------
# Custom theme
# ---------------------------------------------------------------------------
if [ -n "${THEME}" ]; then
  _THEME_REPO_NAME="$(basename "$THEME")"
  git_clone \
    --url "https://github.com/${THEME}" \
    --dir "${OSH_CUSTOM_DIR}/themes/${_THEME_REPO_NAME}"
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
    git_clone \
      --url "https://github.com/${_slug}" \
      --dir "${OSH_CUSTOM_DIR}/plugins/${_PLUGIN_NAME}"
    echo "ℹ️  Installed custom plugin '${_slug}'." >&2
  done
fi

echo "✅ Oh My Bash installation complete." >&2
