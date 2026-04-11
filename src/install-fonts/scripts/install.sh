#!/usr/bin/env bash
# install-fonts main orchestrator.
#
# Installs fonts from Nerd Fonts, direct URLs, and/or GitHub release assets.
#
# Can be run standalone (CLI flags) or as a devcontainer feature (env vars).
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$(cd "$_SELF_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------
# shellcheck source=lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"
# shellcheck source=lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
logging::setup
trap 'logging::cleanup' EXIT

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
__usage__() {
  cat >&2 << 'EOF'
Usage: install.sh [OPTIONS]

Options:
  --nerd_fonts <string>        Comma-separated Nerd Fonts archive names to install
                               (e.g. "Meslo,JetBrainsMono,FiraCode"). Default: "Meslo,JetBrainsMono".
                               Set to empty string to skip Nerd Font downloads.
  --font_urls <urls>           Comma-separated direct font URLs to download.
                               Font files (.ttf/.otf/.woff/.woff2) and archives (.tar.xz/.tar.gz/.tgz/.zip)
                               are installed, deduplicated by PostScript name.
  --gh_release_fonts <slugs>   Comma-separated GitHub slugs (owner/repo or owner/repo@tag).
                               Downloads all font/archive assets from the release,
                               deduplicated by PostScript name.
  --font_dir <path>            Directory where fonts will be installed.
                               Leave empty (default) to auto-detect:
                                 root/container → /usr/share/fonts
                                 Linux user     → $XDG_DATA_HOME/fonts (~/.local/share/fonts)
                                 macOS user     → ~/Library/Fonts
                               Set explicitly to override.
  --p10k_fonts                 Also install Powerlevel10k-specific MesloLGS NF fonts.
  --overwrite                  Overwrite an existing font when its PostScript name collides with
                               a font being installed. Default: skip and log the collision.
  --debug                      Enable debug output (set -x).
  --logfile <path>             Log all output to this file in addition to console.
  -h, --help                   Show this help.
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing — dual-mode: CLI flags or env vars
# ---------------------------------------------------------------------------
if [ "$#" -gt 0 ]; then
  NERD_FONTS=""
  FONT_URLS=""
  GH_RELEASE_FONTS=""
  FONT_DIR=""
  P10K_FONTS=""
  OVERWRITE=""
  DEBUG=""
  LOGFILE=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      --nerd_fonts)
        shift
        NERD_FONTS="$1"
        shift
        ;;
      --font_urls)
        shift
        FONT_URLS="$1"
        shift
        ;;
      --gh_release_fonts)
        shift
        GH_RELEASE_FONTS="$1"
        shift
        ;;
      --font_dir)
        shift
        FONT_DIR="$1"
        shift
        ;;
      --p10k_fonts)
        shift
        P10K_FONTS="$1"
        shift
        ;;
      --overwrite)
        OVERWRITE=true
        shift
        ;;
      --debug)
        DEBUG=true
        shift
        ;;
      --logfile)
        shift
        LOGFILE="$1"
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

# ---------------------------------------------------------------------------
# Defaults (match devcontainer-feature.json)
# ---------------------------------------------------------------------------
: "${NERD_FONTS=Meslo,JetBrainsMono}"
: "${FONT_URLS=}"
: "${GH_RELEASE_FONTS=}"
: "${FONT_DIR=}" # empty → auto-detect below
: "${P10K_FONTS:=false}"
: "${OVERWRITE:=false}"
: "${DEBUG:=false}"
: "${LOGFILE=}"

# Auto-detect font directory when not explicitly set.
if [[ -z "$FONT_DIR" ]]; then
  FONT_DIR="$(os::font_dir)"
fi

ospkg::run --manifest "${_BASE_DIR}/dependencies/base.txt" --check_installed

[[ "${DEBUG:-}" == true ]] && set -x

echo "========================================" >&2
echo "  install-fonts" >&2
echo "========================================" >&2

_FONT_ARGS=(--font_dir "$FONT_DIR")
[ -n "$NERD_FONTS" ] && _FONT_ARGS+=(--nerd_fonts "$NERD_FONTS")
[ -n "$FONT_URLS" ] && _FONT_ARGS+=(--font_urls "$FONT_URLS")
[ -n "$GH_RELEASE_FONTS" ] && _FONT_ARGS+=(--gh_release_fonts "$GH_RELEASE_FONTS")
[[ "$P10K_FONTS" == true ]] && _FONT_ARGS+=(--p10k_fonts)
[[ "$OVERWRITE" == true ]] && _FONT_ARGS+=(--overwrite)
[[ "$DEBUG" == true ]] && _FONT_ARGS+=(--debug)

bash "$_SELF_DIR/install_fonts.sh" "${_FONT_ARGS[@]}"
