#!/usr/bin/env bash
# install_fonts.sh — Install fonts from Nerd Fonts, direct URLs, and GitHub releases.
#
# Nerd Fonts: downloaded by archive name from ryanoasis/nerd-fonts releases.
# font_urls: direct URLs to font files or archives.
# gh_release_fonts: all font/archive assets from a GitHub release.
# p10k_fonts: four MesloLGS NF fonts from romkatv/powerlevel10k-media.
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
  --nerd_fonts <string>        Comma-separated Nerd Fonts archive names (e.g. "Meslo,JetBrainsMono")
  --font_urls <urls>           Comma-separated direct font URLs (font files or archives)
  --gh_release_fonts <slugs>   Comma-separated GitHub slugs (owner/repo or owner/repo@tag)
  --font_dir <string>          Base directory for font installation (default: /usr/share/fonts)
  --p10k_fonts                 Also install Powerlevel10k-specific MesloLGS NF fonts
  --debug                      Enable debug output (set -x)
  -h, --help                   Show this help
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
if [ "$#" -gt 0 ]; then
  NERD_FONTS=""
  FONT_URLS=""
  GH_RELEASE_FONTS=""
  FONT_DIR=""
  P10K_FONTS=false
  DEBUG=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --nerd_fonts)       shift; NERD_FONTS="$1";       shift;;
      --font_urls)        shift; FONT_URLS="$1";        shift;;
      --gh_release_fonts) shift; GH_RELEASE_FONTS="$1"; shift;;
      --font_dir)         shift; FONT_DIR="$1";         shift;;
      --p10k_fonts)       P10K_FONTS=true; shift;;
      --debug)            DEBUG=true; shift;;
      --help|-h)          __usage__;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *)   echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
    esac
  done
fi

: "${NERD_FONTS=Meslo,JetBrainsMono}"
: "${FONT_URLS=}"
: "${GH_RELEASE_FONTS=}"
: "${FONT_DIR:=/usr/share/fonts}"
: "${P10K_FONTS:=false}"
: "${DEBUG:=false}"

[[ "$DEBUG" == true ]] && set -x

# ---------------------------------------------------------------------------
# Install Nerd Fonts from official releases
# ---------------------------------------------------------------------------
if [ -n "$NERD_FONTS" ]; then
  _NF_BASE_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download"

  IFS=',' read -r -a _FONT_LIST <<< "$NERD_FONTS"
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
# Install fonts from direct URLs
# ---------------------------------------------------------------------------
if [ -n "$FONT_URLS" ]; then
  IFS=',' read -r -a _URL_LIST <<< "$FONT_URLS"
  for _url in "${_URL_LIST[@]}"; do
    _url="${_url// /}"
    [ -z "$_url" ] && continue

    # Derive basename from URL (strip query string first).
    _basename="${_url%%\?*}"
    _basename="${_basename##*/}"

    case "$_basename" in
      *.tar.xz|*.tar.gz|*.tgz|*.zip)
        # Strip all extensions to form the subdirectory name.
        _dir_name="${_basename%.tar.xz}"; _dir_name="${_dir_name%.tar.gz}"
        _dir_name="${_dir_name%.tgz}";   _dir_name="${_dir_name%.zip}"
        _DEST_DIR="${FONT_DIR}/${_dir_name}"
        if [ -d "$_DEST_DIR" ] && [ -n "$(find "$_DEST_DIR" -maxdepth 1 \( -name '*.ttf' -o -name '*.otf' \) 2>/dev/null | head -1)" ]; then
          echo "ℹ️  '${_dir_name}' already present — skipping." >&2; continue
        fi
        echo "ℹ️  Downloading font archive '${_basename}'..." >&2
        _ARCHIVE="$(mktemp)"
        if fetch_with_retry 3 curl -fsSL "$_url" -o "$_ARCHIVE"; then
          mkdir -p "$_DEST_DIR"
          case "$_basename" in
            *.tar.xz)       tar -xJf "$_ARCHIVE" -C "$_DEST_DIR";;
            *.tar.gz|*.tgz) tar -xzf "$_ARCHIVE" -C "$_DEST_DIR";;
            *.zip)
              if ! command -v unzip > /dev/null 2>&1; then
                echo "⚠️  'unzip' not found — cannot extract '${_basename}'. Skipping." >&2
                rm -f "$_ARCHIVE"; continue
              fi
              unzip -q -o "$_ARCHIVE" -d "$_DEST_DIR";;
          esac
          find "$_DEST_DIR" -maxdepth 1 -type f \
            ! -name '*.ttf' ! -name '*.otf' ! -name '*.woff' ! -name '*.woff2' \
            -delete 2>/dev/null || true
          chmod 755 "$_DEST_DIR"
          find "$_DEST_DIR" -type f \( -name '*.ttf' -o -name '*.otf' \) -exec chmod 644 {} +
          echo "✅ Installed '${_dir_name}' to '${_DEST_DIR}'." >&2
        else
          echo "⚠️  Could not download '${_basename}' — skipping." >&2
        fi
        rm -f "$_ARCHIVE"
        ;;
      *.ttf|*.otf|*.woff|*.woff2)
        _DEST_FILE="${FONT_DIR}/${_basename}"
        if [ -f "$_DEST_FILE" ]; then
          echo "ℹ️  '${_basename}' already present — skipping." >&2; continue
        fi
        echo "ℹ️  Downloading font file '${_basename}'..." >&2
        mkdir -p "$FONT_DIR"
        if fetch_with_retry 3 curl -fsSL "$_url" -o "$_DEST_FILE"; then
          chmod 644 "$_DEST_FILE"
          echo "✅ Installed '${_basename}' to '${FONT_DIR}'." >&2
        else
          echo "⚠️  Could not download '${_basename}' — skipping." >&2
          rm -f "$_DEST_FILE"
        fi
        ;;
      *)
        echo "⚠️  Unrecognized extension in URL '${_url}' — skipping." >&2
        ;;
    esac
  done
fi

# ---------------------------------------------------------------------------
# Install fonts from GitHub releases
# ---------------------------------------------------------------------------
if [ -n "$GH_RELEASE_FONTS" ]; then
  IFS=',' read -r -a _SLUG_LIST <<< "$GH_RELEASE_FONTS"
  for _slug in "${_SLUG_LIST[@]}"; do
    _slug="${_slug// /}"
    [ -z "$_slug" ] && continue

    # Split owner/repo@tag into repo path and optional tag.
    _repo_path="${_slug%@*}"
    _tag=""
    [[ "$_slug" == *@* ]] && _tag="${_slug#*@}"

    # Derive install directory name from repo name (last path component).
    _repo_name="${_repo_path##*/}"
    _DEST_DIR="${FONT_DIR}/${_repo_name}"

    if [ -d "$_DEST_DIR" ] && [ -n "$(find "$_DEST_DIR" -type f \( -name '*.ttf' -o -name '*.otf' \) 2>/dev/null | head -1)" ]; then
      echo "ℹ️  '${_repo_name}' fonts already present in '${_DEST_DIR}' — skipping." >&2
      continue
    fi

    # Build GitHub API URL.
    if [ -n "$_tag" ]; then
      _API_URL="https://api.github.com/repos/${_repo_path}/releases/tags/${_tag}"
    else
      _API_URL="https://api.github.com/repos/${_repo_path}/releases/latest"
    fi

    echo "ℹ️  Querying release assets for '${_slug}'..." >&2
    _API_RESPONSE="$(mktemp)"
    if ! fetch_with_retry 3 curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$_API_URL" -o "$_API_RESPONSE"; then
      echo "⚠️  Could not query GitHub release for '${_slug}' — skipping." >&2
      rm -f "$_API_RESPONSE"; continue
    fi

    # Extract download URLs for font/archive assets.
    # Prefer archives over individual font files to avoid duplication.
    mapfile -t _ALL_ASSET_URLS < <(
      grep '"browser_download_url"' "$_API_RESPONSE" \
        | grep -oE 'https://[^"]+' \
        | grep -iE '\.(ttf|otf|woff2?|tar\.xz|tar\.gz|tgz|zip)$'
    )
    rm -f "$_API_RESPONSE"

    if [ ${#_ALL_ASSET_URLS[@]} -eq 0 ]; then
      echo "⚠️  No font or archive assets found in '${_slug}' release — skipping." >&2
      continue
    fi

    # Prefer archives; fall back to individual font files if no archives exist.
    _ARCHIVE_URLS=()
    _FONTFILE_URLS=()
    for _asset_url in "${_ALL_ASSET_URLS[@]}"; do
      case "${_asset_url##*/}" in
        *.tar.xz|*.tar.gz|*.tgz|*.zip) _ARCHIVE_URLS+=("$_asset_url");;
        *)                              _FONTFILE_URLS+=("$_asset_url");;
      esac
    done
    if [ ${#_ARCHIVE_URLS[@]} -gt 0 ]; then
      _DOWNLOAD_URLS=("${_ARCHIVE_URLS[@]}")
    else
      _DOWNLOAD_URLS=("${_FONTFILE_URLS[@]}")
    fi

    mkdir -p "$_DEST_DIR"
    for _asset_url in "${_DOWNLOAD_URLS[@]}"; do
      _asset_basename="${_asset_url##*/}"
      echo "ℹ️  Downloading '${_asset_basename}' from '${_slug}' release..." >&2
      _ARCHIVE="$(mktemp)"
      if ! fetch_with_retry 3 curl -fsSL "$_asset_url" -o "$_ARCHIVE"; then
        echo "⚠️  Could not download '${_asset_basename}' — skipping." >&2
        rm -f "$_ARCHIVE"; continue
      fi
      case "$_asset_basename" in
        *.tar.xz)       tar -xJf "$_ARCHIVE" -C "$_DEST_DIR"; rm -f "$_ARCHIVE";;
        *.tar.gz|*.tgz) tar -xzf "$_ARCHIVE" -C "$_DEST_DIR"; rm -f "$_ARCHIVE";;
        *.zip)
          if ! command -v unzip > /dev/null 2>&1; then
            echo "⚠️  'unzip' not found — cannot extract '${_asset_basename}'. Skipping." >&2
            rm -f "$_ARCHIVE"; continue
          fi
          unzip -q -o "$_ARCHIVE" -d "$_DEST_DIR"; rm -f "$_ARCHIVE";;
        *)  mv "$_ARCHIVE" "${_DEST_DIR}/${_asset_basename}";;
      esac
    done

    chmod 755 "$_DEST_DIR"
    find "$_DEST_DIR" -type f \( -name '*.ttf' -o -name '*.otf' \) -exec chmod 644 {} +
    echo "✅ Installed '${_repo_name}' fonts to '${_DEST_DIR}'." >&2
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
