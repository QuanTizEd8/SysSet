#!/usr/bin/env bash
# install_fonts.sh — Install Nerd Fonts and/or Powerlevel10k MesloLGS fonts.
#
# Downloads font archives from the official nerd-fonts GitHub releases and
# extracts them into FONT_DIR.  Optionally also downloads the Powerlevel10k-
# specific MesloLGS NF fonts from romkatv/powerlevel10k-media.
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
Usage: install_fonts.sh [OPTIONS]

Options:
  --font_names <string>  Comma-separated list of Nerd Fonts archive names
                         (e.g. "Meslo,JetBrainsMono,FiraCode")
  --font_dir <string>    Base directory for font installation (default: /usr/share/fonts)
  --p10k_fonts           Also install Powerlevel10k-specific MesloLGS NF fonts
  --debug                Enable debug output (set -x)
  -h, --help             Show this help
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
if [ "$#" -gt 0 ]; then
  FONT_NAMES=""
  FONT_DIR=""
  P10K_FONTS=false
  DEBUG=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --font_names) shift; FONT_NAMES="$1"; shift;;
      --font_dir) shift; FONT_DIR="$1"; shift;;
      --p10k_fonts) P10K_FONTS=true; shift;;
      --debug) DEBUG=true; shift;;
      --help|-h) __usage__;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *) echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
    esac
  done
fi

: "${FONT_NAMES=Meslo,JetBrainsMono}"
: "${FONT_DIR:=/usr/share/fonts}"
: "${P10K_FONTS:=false}"
: "${DEBUG:=false}"

[[ "$DEBUG" == true ]] && set -x

# ---------------------------------------------------------------------------
# Install Nerd Fonts from official releases
# ---------------------------------------------------------------------------
if [ -n "$FONT_NAMES" ]; then
  _NF_BASE_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download"

  IFS=',' read -r -a _FONT_LIST <<< "$FONT_NAMES"
  for _font_name in "${_FONT_LIST[@]}"; do
    _font_name="${_font_name// /}"
    [ -z "$_font_name" ] && continue

    _DEST_DIR="${FONT_DIR}/${_font_name}"
    if [ -d "$_DEST_DIR" ] && [ -n "$(find "$_DEST_DIR" -maxdepth 1 \( -name '*.ttf' -o -name '*.otf' \) 2>/dev/null | head -1)" ]; then
      echo "ℹ️  '${_font_name}' fonts already present in '${_DEST_DIR}' — skipping." >&2
      continue
    fi

    echo "ℹ️  Downloading Nerd Font '${_font_name}'..." >&2
    _ARCHIVE="$(mktemp)"
    if fetch_with_retry 3 curl -fsSL "${_NF_BASE_URL}/${_font_name}.tar.xz" -o "$_ARCHIVE"; then
      mkdir -p "$_DEST_DIR"
      tar -xJf "$_ARCHIVE" -C "$_DEST_DIR"
    else
      echo "⚠️  Could not download '${_font_name}' from nerd-fonts releases — skipping." >&2
      rm -f "$_ARCHIVE"
      continue
    fi
    rm -f "$_ARCHIVE"

    # Clean up non-font files that may be in the archive (e.g. LICENSE, README).
    find "$_DEST_DIR" -maxdepth 1 -type f \
      ! -name '*.ttf' ! -name '*.otf' ! -name '*.woff' ! -name '*.woff2' \
      -delete 2>/dev/null || true

    chmod 755 "$_DEST_DIR"
    find "$_DEST_DIR" -type f \( -name '*.ttf' -o -name '*.otf' \) -exec chmod 644 {} +
    echo "✅ Installed '${_font_name}' to '${_DEST_DIR}'." >&2
  done
fi

# ---------------------------------------------------------------------------
# Install Powerlevel10k-specific MesloLGS NF fonts
# ---------------------------------------------------------------------------
if [[ "$P10K_FONTS" == true ]]; then
  _P10K_DIR="${FONT_DIR}/MesloLGS-NF"
  if [ -d "$_P10K_DIR" ] && [ -n "$(find "$_P10K_DIR" -maxdepth 1 -name '*.ttf' 2>/dev/null | head -1)" ]; then
    echo "ℹ️  MesloLGS NF (p10k) fonts already present — skipping." >&2
  else
    echo "ℹ️  Downloading Powerlevel10k MesloLGS NF fonts..." >&2
    mkdir -p "$_P10K_DIR"
    _P10K_BASE_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
    _P10K_FONT_FILES=(
      "MesloLGS%20NF%20Regular.ttf"
      "MesloLGS%20NF%20Bold.ttf"
      "MesloLGS%20NF%20Italic.ttf"
      "MesloLGS%20NF%20Bold%20Italic.ttf"
    )
    for _FONT in "${_P10K_FONT_FILES[@]}"; do
      _LOCAL_NAME="$(printf '%b' "${_FONT//%/\\x}")"
      fetch_with_retry 3 curl -fsSL "${_P10K_BASE_URL}/${_FONT}" -o "${_P10K_DIR}/${_LOCAL_NAME}"
    done
    chmod 755 "$_P10K_DIR"
    chmod 644 "$_P10K_DIR"/*.ttf
    echo "✅ Installed MesloLGS NF (p10k) fonts to '${_P10K_DIR}'." >&2
  fi
fi

# ---------------------------------------------------------------------------
# Refresh font cache
# ---------------------------------------------------------------------------
if command -v fc-cache > /dev/null 2>&1; then
  echo "ℹ️  Refreshing font cache..." >&2
  fc-cache -f "$FONT_DIR" 2>/dev/null || true
fi

echo "✅ Font installation complete." >&2
