#!/usr/bin/env bash
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$(cd "$_SELF_DIR/.." && pwd)"

# shellcheck source=lib/ospkg.sh
. "$_SELF_DIR/_lib/ospkg.sh"
# shellcheck source=lib/logging.sh
. "$_SELF_DIR/_lib/logging.sh"
logging__setup
echo "↪️ Script entry: Font Installation" >&2
# Override _cleanup_hook in the hand-written section for feature-specific
# cleanup (e.g. removing temp files). Do NOT call logging__cleanup there;
# _on_exit owns that call and guarantees it runs exactly once, last.
# shellcheck disable=SC2329
_cleanup_hook() { return; }
# shellcheck disable=SC2329
_on_exit() {
  local _rc=$?
  _cleanup_hook
  [[ "${KEEP_CACHE:-true}" != true ]] && ospkg__clean
  if [[ $_rc -eq 0 ]]; then
    echo "✅ Font Installation script finished successfully." >&2
  else
    echo "❌ Font Installation script exited with error ${_rc}." >&2
  fi
  logging__cleanup
  return
}
trap '_on_exit' EXIT

__usage__() {
  cat << 'EOF'
Usage: install.sh [OPTIONS]

Options:
  --nerd_fonts <value>  (repeatable)        Nerd Fonts archive names to install (e.g. `Meslo`, `FiraCode`, `Hack`). Leave empty to skip Nerd Font downloads.
  --font_urls <value>  (repeatable)         Direct URLs to download. Font files (`.ttf`, `.otf`, `.woff`, `.woff2`) and archives (`.tar.xz`, `.tar.gz`, `.tgz`, `.zip`) are installed under a namespaced path derived from the URL. Fonts are deduplicated by PostScript name.
  --gh_release_fonts <value>  (repeatable)  GitHub slugs in `owner/repo` or `owner/repo@tag` form. All font and archive assets from the release are installed under `gh/<owner>/<repo>/<tag>/<id>/`. Without a tag, the latest release is used. Fonts are deduplicated by PostScript name.
  --p10k_fonts {true,false}                 Install the four MesloLGS NF fonts required by Powerlevel10k under `p10k/MesloLGS-NF/`. (default: "false")
  --overwrite {true,false}                  When a font with the same PostScript name is already installed, overwrite it instead of skipping. Default is to skip and log. (default: "false")
  --font_dir <value>                        Font installation directory. Leave empty to auto-detect: root/container -> /usr/share/fonts; Linux user -> $XDG_DATA_HOME/fonts; macOS user -> ~/Library/Fonts.
  --keep_cache {true,false}                 Keep the package manager cache after installation. By default, the package manager cache is removed after installation to reduce image layer size. Set this flag to true to keep the cache, which may speed up subsequent installations at the cost of larger image layers. (default: "false")
  --debug {true,false}                      Enable debug output. This adds `set -x` to the installer script, which prints each command before executing it. (default: "false")
  --logfile <value>                         Log all output (stdout + stderr) to this file in addition to console.
  -h, --help                                Show this help
EOF
  return
}

if [ "$#" -gt 0 ]; then
  echo "ℹ️ Script called with arguments: $*" >&2
  NERD_FONTS=()
  FONT_URLS=()
  GH_RELEASE_FONTS=()
  P10K_FONTS=false
  OVERWRITE=false
  FONT_DIR=""
  KEEP_CACHE=false
  DEBUG=false
  LOGFILE=""
  while [ "$#" -gt 0 ]; do
    case $1 in
      --nerd_fonts)
        shift
        NERD_FONTS+=("$1")
        echo "📩 Read argument 'nerd_fonts': '$1'" >&2
        shift
        ;;
      --font_urls)
        shift
        FONT_URLS+=("$1")
        echo "📩 Read argument 'font_urls': '$1'" >&2
        shift
        ;;
      --gh_release_fonts)
        shift
        GH_RELEASE_FONTS+=("$1")
        echo "📩 Read argument 'gh_release_fonts': '$1'" >&2
        shift
        ;;
      --p10k_fonts)
        shift
        P10K_FONTS="$1"
        echo "📩 Read argument 'p10k_fonts': '${P10K_FONTS}'" >&2
        shift
        ;;
      --overwrite)
        shift
        OVERWRITE="$1"
        echo "📩 Read argument 'overwrite': '${OVERWRITE}'" >&2
        shift
        ;;
      --font_dir)
        shift
        FONT_DIR="$1"
        echo "📩 Read argument 'font_dir': '${FONT_DIR}'" >&2
        shift
        ;;
      --keep_cache)
        shift
        KEEP_CACHE="$1"
        echo "📩 Read argument 'keep_cache': '${KEEP_CACHE}'" >&2
        shift
        ;;
      --debug)
        shift
        DEBUG="$1"
        echo "📩 Read argument 'debug': '${DEBUG}'" >&2
        shift
        ;;
      --logfile)
        shift
        LOGFILE="$1"
        echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
        shift
        ;;
      -h | --help)
        __usage__
        exit 0
        ;;
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
else
  echo "ℹ️ Script called with no arguments. Read environment variables." >&2
  if [ "${NERD_FONTS+defined}" ]; then
    if [ -n "${NERD_FONTS-}" ]; then
      mapfile -t NERD_FONTS < <(printf '%s\n' "${NERD_FONTS}" | grep -v '^$')
      for _item in "${NERD_FONTS[@]}"; do
        echo "📩 Read argument 'nerd_fonts': '$_item'" >&2
      done
    else
      NERD_FONTS=()
    fi
  fi
  if [ "${FONT_URLS+defined}" ]; then
    if [ -n "${FONT_URLS-}" ]; then
      mapfile -t FONT_URLS < <(printf '%s\n' "${FONT_URLS}" | grep -v '^$')
      for _item in "${FONT_URLS[@]}"; do
        echo "📩 Read argument 'font_urls': '$_item'" >&2
      done
    else
      FONT_URLS=()
    fi
  fi
  if [ "${GH_RELEASE_FONTS+defined}" ]; then
    if [ -n "${GH_RELEASE_FONTS-}" ]; then
      mapfile -t GH_RELEASE_FONTS < <(printf '%s\n' "${GH_RELEASE_FONTS}" | grep -v '^$')
      for _item in "${GH_RELEASE_FONTS[@]}"; do
        echo "📩 Read argument 'gh_release_fonts': '$_item'" >&2
      done
    else
      GH_RELEASE_FONTS=()
    fi
  fi
  [ "${P10K_FONTS+defined}" ] && echo "📩 Read argument 'p10k_fonts': '${P10K_FONTS}'" >&2
  [ "${OVERWRITE+defined}" ] && echo "📩 Read argument 'overwrite': '${OVERWRITE}'" >&2
  [ "${FONT_DIR+defined}" ] && echo "📩 Read argument 'font_dir': '${FONT_DIR}'" >&2
  [ "${KEEP_CACHE+defined}" ] && echo "📩 Read argument 'keep_cache': '${KEEP_CACHE}'" >&2
  [ "${DEBUG+defined}" ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${LOGFILE+defined}" ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
fi

[[ "${DEBUG:-}" == true ]] && set -x

# Apply defaults.
[ "${NERD_FONTS+defined}" ] || {
  mapfile -t NERD_FONTS < <(printf '%s' $'Meslo\nJetBrainsMono' | grep -v '^$')
  echo "ℹ️ Argument 'nerd_fonts' set to default value 'Meslo, JetBrainsMono'." >&2
}
[ "${FONT_URLS+defined}" ] || {
  FONT_URLS=()
  echo "ℹ️ Argument 'font_urls' set to default value '(empty)'." >&2
}
[ "${GH_RELEASE_FONTS+defined}" ] || {
  GH_RELEASE_FONTS=()
  echo "ℹ️ Argument 'gh_release_fonts' set to default value '(empty)'." >&2
}
[ "${P10K_FONTS+defined}" ] || {
  P10K_FONTS=false
  echo "ℹ️ Argument 'p10k_fonts' set to default value 'false'." >&2
}
[ "${OVERWRITE+defined}" ] || {
  OVERWRITE=false
  echo "ℹ️ Argument 'overwrite' set to default value 'false'." >&2
}
[ "${FONT_DIR+defined}" ] || {
  FONT_DIR=""
  echo "ℹ️ Argument 'font_dir' set to default value ''." >&2
}
[ "${KEEP_CACHE+defined}" ] || {
  KEEP_CACHE=false
  echo "ℹ️ Argument 'keep_cache' set to default value 'false'." >&2
}
[ "${DEBUG+defined}" ] || {
  DEBUG=false
  echo "ℹ️ Argument 'debug' set to default value 'false'." >&2
}
[ "${LOGFILE+defined}" ] || {
  LOGFILE=""
  echo "ℹ️ Argument 'logfile' set to default value ''." >&2
}

ospkg__run --manifest "${_BASE_DIR}/dependencies/base.yaml" --skip_installed

# END OF AUTOGENERATED BLOCK

# shellcheck source=lib/file.sh
. "$_SELF_DIR/_lib/file.sh"
# shellcheck source=lib/net.sh
. "$_SELF_DIR/_lib/net.sh"
# shellcheck source=lib/github.sh
. "$_SELF_DIR/_lib/github.sh"

# Constants
# ---------------------------------------------------------------------------
_P10K_BASE_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
_NF_BASE_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download"

# Helper: ensure the timestamped install directory exists (lazy)
# ---------------------------------------------------------------------------
_ensure_install_dir() {
  if [[ -z "$_INSTALL_DIR" ]]; then
    _INSTALL_DIR="${FONT_DIR}/sysset-install-fonts-$(date +%s)"
    mkdir -p "$_INSTALL_DIR"
  fi
}

# Helper: url_to_namespace <url>
# Returns: url/<host>/<path-without-filename>
# e.g. https://example.com/fonts/MyFont.tar.xz → url/example.com/fonts
# ---------------------------------------------------------------------------
url_to_namespace() {
  local _url="$1"
  # Strip protocol and query string
  local _noscheme="${_url#*://}"
  _noscheme="${_noscheme%%\?*}"
  # Strip trailing filename component
  local _dir="${_noscheme%/*}"
  printf 'url/%s' "$_dir"
}

# Helper: _do_install_font <src_file> <dest_rel_path> <tab_sep_psnames>
# Inner function — psnames must be pre-computed by the caller.
# <dest_rel_path> is relative to _INSTALL_DIR, including the filename.
# Pass empty psnames string for WOFF/WOFF2 (copies unconditionally).
# ---------------------------------------------------------------------------
_do_install_font() {
  local _src="$1" _rel="$2" _psnames_str="$3"
  # Use the destination path (which preserves the original filename) for
  # extension detection — _src may be a mktemp path with no extension.
  local _basename
  _basename="$(basename "$_rel")"

  case "$_basename" in
    *.woff | *.woff2)
      # No PostScript dedup for WOFF — copy unconditionally.
      _ensure_install_dir
      local _dest="${_INSTALL_DIR}/${_rel}"
      mkdir -p "$(dirname "$_dest")"
      cp "$_src" "$_dest"
      chmod 644 "$_dest"
      return 0
      ;;
  esac

  # Empty psnames for a non-WOFF means invalid/unrecognized font — skip silently.
  [[ -z "$_psnames_str" ]] && return 0

  # Parse tab-separated psnames.
  local _psnames=()
  IFS=$'\t' read -r -a _psnames <<< "$_psnames_str"

  [[ ${#_psnames[@]} -eq 0 ]] && return 0 # Not a valid font — skip silently.

  # Check for collision with any face in this file.
  local _collision_name=""
  for _n in "${_psnames[@]}"; do
    if [[ -n "${_SEEN_NAMES[$_n]+_}" ]]; then
      _collision_name="$_n"
      break
    fi
  done

  if [[ -n "$_collision_name" ]]; then
    if [[ "$OVERWRITE" == true ]]; then
      echo "ℹ️  Font '${_collision_name}' already registered — overwriting '${_basename}'." >&2
    else
      echo "ℹ️  Font '${_collision_name}' already registered — skipping '${_basename}'." >&2
      return 0
    fi
  fi

  _ensure_install_dir
  local _dest="${_INSTALL_DIR}/${_rel}"
  mkdir -p "$(dirname "$_dest")"
  cp "$_src" "$_dest"
  chmod 644 "$_dest"

  # Register all faces of this file in _SEEN_NAMES.
  for _n in "${_psnames[@]}"; do
    _SEEN_NAMES["$_n"]=1
  done
}

# Helper: install_font_file <src_file> <dest_rel_path>
# Public API for single file installs (p10k, direct URL font files).
# Calls fc-query itself; delegates to _do_install_font.
# ---------------------------------------------------------------------------
install_font_file() {
  local _src="$1" _rel="$2"

  # Query all PostScript names (handles TTC multi-face).
  # For WOFF/WOFF2, fc-query returns empty; _do_install_font handles that case
  # by checking the extension from _rel.
  local _psnames_str="" _pn
  while IFS= read -r _pn; do
    [[ -z "$_pn" ]] && continue
    if [[ -n "$_psnames_str" ]]; then
      _psnames_str+=$'\t'"$_pn"
    else _psnames_str="$_pn"; fi
  done < <(fc-query --format='%{postscriptname}\n' "$_src" 2> /dev/null || true)

  _do_install_font "$_src" "$_rel" "$_psnames_str"
}

# Helper: install_archive_contents <tmpdir> <namespace_subdir>
# Runs ONE batched fc-query on all TTF/OTF in tmpdir (fast for large archives).
# WOFF/WOFF2 are passed through without PostScript checking.
# ---------------------------------------------------------------------------
install_archive_contents() {
  local _tmpdir="$1" _ns="$2"

  # Find all font files in the archive.
  local _font_files=()
  while IFS= read -r -d '' _f; do
    _font_files+=("$_f")
  done < <(find "$_tmpdir" -type f \( -name '*.ttf' -o -name '*.otf' \
    -o -name '*.woff' -o -name '*.woff2' \) -print0)

  if [[ ${#_font_files[@]} -eq 0 ]]; then
    echo "⚠️  No font files found in archive." >&2
    return 0
  fi

  # Batch fc-query for all TTF/OTF files: build file→tab_sep_psnames map.
  # fc-query outputs one line per face; %{file} repeats for multi-face files.
  declare -A _batch_psnames=()
  local _queryfiles=()
  for _f in "${_font_files[@]}"; do
    case "$_f" in *.ttf | *.otf) _queryfiles+=("$_f") ;; esac
  done
  if [[ ${#_queryfiles[@]} -gt 0 ]]; then
    while IFS=$'\t' read -r _fname _pname; do
      [[ -z "$_fname" || -z "$_pname" ]] && continue
      if [[ -n "${_batch_psnames[$_fname]+_}" ]]; then
        _batch_psnames["$_fname"]+=$'\t'"$_pname"
      else
        _batch_psnames["$_fname"]="$_pname"
      fi
    done < <(fc-query --format='%{file}\t%{postscriptname}\n' \
      "${_queryfiles[@]}" 2> /dev/null || true)
  fi

  for _f in "${_font_files[@]}"; do
    local _rel_path="${_f#"${_tmpdir}"/}"
    local _psnames_str
    case "$_f" in
      *.woff | *.woff2) _psnames_str="" ;;
      *) _psnames_str="${_batch_psnames[$_f]:-}" ;;
    esac
    _do_install_font "$_f" "${_ns}/${_rel_path}" "$_psnames_str"
  done
}

# Auto-detect font directory when not explicitly set.
if [[ -z "$FONT_DIR" ]]; then
  FONT_DIR="$(os__font_dir)"
fi

# Sources are processed in priority order: p10k → nerd → gh → url.
# Fonts are deduplicated by PostScript name. Archives are extracted to a temp
# directory; only font files passing the deduplication check are copied to the
# final install location.
#
# All installed fonts land under:
#   <font_dir>/sysset-install-fonts-<timestamp>/
#     p10k/MesloLGS-NF/
#     nerd/<FontName>/
#     gh/<owner>/<repo>/<tag_name>/<release_id>/
#     url/<host>/<path>/

# ---------------------------------------------------------------------------
# State: seen PostScript names + lazy install directory
# ---------------------------------------------------------------------------
declare -A _SEEN_NAMES=()
_INSTALL_DIR=""

# Populate _SEEN_NAMES from all .ttf/.otf already present in FONT_DIR.
# WOFF/WOFF2 are excluded — fc-query does not handle them.
if [[ -d "$FONT_DIR" ]]; then
  while IFS= read -r _psname; do
    [[ -n "$_psname" ]] && _SEEN_NAMES["$_psname"]=1
  done < <(find "$FONT_DIR" -type f \( -name '*.ttf' -o -name '*.otf' \) -print0 |
    xargs -0 -r fc-query --format='%{postscriptname}\n' 2> /dev/null || true)
fi

# ---------------------------------------------------------------------------
# Step 1 — Powerlevel10k MesloLGS NF fonts (highest priority)
# ---------------------------------------------------------------------------
if [[ "$P10K_FONTS" == true ]]; then
  echo "ℹ️  Installing Powerlevel10k MesloLGS NF fonts..." >&2
  _P10K_FONT_FILES=(
    "MesloLGS%20NF%20Regular.ttf"
    "MesloLGS%20NF%20Bold.ttf"
    "MesloLGS%20NF%20Italic.ttf"
    "MesloLGS%20NF%20Bold%20Italic.ttf"
  )
  for _FONT in "${_P10K_FONT_FILES[@]}"; do
    _LOCAL_NAME="$(printf '%b' "${_FONT//%/\\x}")"
    _TMPFILE="$(mktemp)"
    if net__fetch_url_file "${_P10K_BASE_URL}/${_FONT}" "$_TMPFILE"; then
      install_font_file "$_TMPFILE" "p10k/MesloLGS-NF/${_LOCAL_NAME}"
    else
      echo "⚠️  Could not download '${_LOCAL_NAME}' — skipping." >&2
    fi
    rm -f "$_TMPFILE"
  done
  echo "✅ Powerlevel10k MesloLGS NF fonts processed." >&2
fi

# ---------------------------------------------------------------------------
# Step 2 — Nerd Fonts from official releases
# ---------------------------------------------------------------------------
if [[ "${#NERD_FONTS[@]}" -gt 0 ]]; then
  for _font_name in "${NERD_FONTS[@]}"; do
    [[ -z "$_font_name" ]] && continue

    echo "ℹ️  Downloading Nerd Font '${_font_name}'..." >&2
    _ARCHIVE="$(mktemp)"
    _TMPDIR="$(mktemp -d)"
    if net__fetch_url_file "${_NF_BASE_URL}/${_font_name}.tar.xz" "$_ARCHIVE"; then
      if file__extract_archive "$_ARCHIVE" "$_TMPDIR" "${_font_name}.tar.xz"; then
        install_archive_contents "$_TMPDIR" "nerd/${_font_name}"
        echo "✅ Nerd Font '${_font_name}' processed." >&2
      fi
    else
      echo "⚠️  Could not download '${_font_name}' from nerd-fonts releases — skipping." >&2
    fi
    rm -f "$_ARCHIVE"
    rm -rf "$_TMPDIR"
  done
fi

# ---------------------------------------------------------------------------
# Step 3 — GitHub release fonts
# ---------------------------------------------------------------------------
if [[ "${#GH_RELEASE_FONTS[@]}" -gt 0 ]]; then
  for _slug in "${GH_RELEASE_FONTS[@]}"; do
    [[ -z "$_slug" ]] && continue

    _repo_path="${_slug%@*}"
    _tag=""
    [[ "$_slug" == *@* ]] && _tag="${_slug#*@}"
    _owner="${_repo_path%%/*}"
    _repo_name="${_repo_path##*/}"

    echo "ℹ️  Querying release assets for '${_slug}'..." >&2
    _API_RESPONSE="$(mktemp)"
    _fetch_args=()
    [[ -n "$_tag" ]] && _fetch_args+=(--tag "$_tag")
    if ! github__fetch_release_json "$_repo_path" "${_fetch_args[@]}" --dest "$_API_RESPONSE"; then
      echo "⚠️  Could not query GitHub release for '${_slug}' — skipping." >&2
      rm -f "$_API_RESPONSE"
      continue
    fi

    # Extract tag_name and release id for namespace.
    _tag_name="$(grep '"tag_name"' "$_API_RESPONSE" | grep -oE '"[^"]+"' | tail -1 | tr -d '"')"
    _release_id="$(grep -m1 '"id"' "$_API_RESPONSE" | grep -oE '[0-9]+')"
    _NS="gh/${_owner}/${_repo_name}/${_tag_name}/${_release_id}"

    # Extract all font/archive asset URLs.
    mapfile -t _ALL_ASSET_URLS < <(
      grep '"browser_download_url"' "$_API_RESPONSE" |
        grep -oE 'https://[^"]+' |
        grep -iE '\.(ttf|otf|woff2?|tar\.xz|tar\.gz|tgz|zip)$'
    )
    rm -f "$_API_RESPONSE"

    if [[ ${#_ALL_ASSET_URLS[@]} -eq 0 ]]; then
      echo "⚠️  No font or archive assets found in '${_slug}' release — skipping." >&2
      continue
    fi

    # Prefer archives; fall back to individual font files if no archives exist.
    _ARCHIVE_URLS=()
    _FONTFILE_URLS=()
    for _asset_url in "${_ALL_ASSET_URLS[@]}"; do
      case "${_asset_url##*/}" in
        *.tar.xz | *.tar.gz | *.tgz | *.zip) _ARCHIVE_URLS+=("$_asset_url") ;;
        *) _FONTFILE_URLS+=("$_asset_url") ;;
      esac
    done
    if [[ ${#_ARCHIVE_URLS[@]} -gt 0 ]]; then
      _DOWNLOAD_URLS=("${_ARCHIVE_URLS[@]}")
    else
      _DOWNLOAD_URLS=("${_FONTFILE_URLS[@]}")
    fi

    for _asset_url in "${_DOWNLOAD_URLS[@]}"; do
      _asset_basename="${_asset_url##*/}"
      echo "ℹ️  Downloading '${_asset_basename}' from '${_slug}' release..." >&2
      _ARCHIVE="$(mktemp)"
      if ! net__fetch_url_file "$_asset_url" "$_ARCHIVE"; then
        echo "⚠️  Could not download '${_asset_basename}' — skipping." >&2
        rm -f "$_ARCHIVE"
        continue
      fi
      case "$_asset_basename" in
        *.tar.xz | *.tar.gz | *.tgz | *.zip)
          _TMPDIR="$(mktemp -d)"
          if file__extract_archive "$_ARCHIVE" "$_TMPDIR" "$_asset_basename"; then
            install_archive_contents "$_TMPDIR" "$_NS"
          fi
          rm -rf "$_TMPDIR"
          ;;
        *)
          install_font_file "$_ARCHIVE" "${_NS}/${_asset_basename}"
          ;;
      esac
      rm -f "$_ARCHIVE"
    done
    echo "✅ GitHub release '${_slug}' processed." >&2
  done
fi

# ---------------------------------------------------------------------------
# Step 4 — Direct URL fonts
# ---------------------------------------------------------------------------
if [[ "${#FONT_URLS[@]}" -gt 0 ]]; then
  for _url in "${FONT_URLS[@]}"; do
    [[ -z "$_url" ]] && continue

    _NS="$(url_to_namespace "$_url")"

    # Derive basename from URL (strip query string first).
    _basename="${_url%%\?*}"
    _basename="${_basename##*/}"

    case "$_basename" in
      *.tar.xz | *.tar.gz | *.tgz | *.zip)
        echo "ℹ️  Downloading font archive '${_basename}'..." >&2
        _ARCHIVE="$(mktemp)"
        _TMPDIR="$(mktemp -d)"
        if net__fetch_url_file "$_url" "$_ARCHIVE"; then
          if file__extract_archive "$_ARCHIVE" "$_TMPDIR" "$_basename"; then
            install_archive_contents "$_TMPDIR" "$_NS"
            echo "✅ Font archive '${_basename}' processed." >&2
          fi
        else
          echo "⚠️  Could not download '${_basename}' — skipping." >&2
        fi
        rm -f "$_ARCHIVE"
        rm -rf "$_TMPDIR"
        ;;
      *.ttf | *.otf | *.woff | *.woff2)
        echo "ℹ️  Downloading font file '${_basename}'..." >&2
        _TMPFILE="$(mktemp)"
        if net__fetch_url_file "$_url" "$_TMPFILE"; then
          install_font_file "$_TMPFILE" "${_NS}/${_basename}"
          echo "✅ Font file '${_basename}' processed." >&2
        else
          echo "⚠️  Could not download '${_basename}' — skipping." >&2
        fi
        rm -f "$_TMPFILE"
        ;;
      *)
        echo "⚠️  Unrecognized extension in URL '${_url}' — skipping." >&2
        ;;
    esac
  done
fi

# ---------------------------------------------------------------------------
# Post-install: fix directory permissions and refresh font cache
# ---------------------------------------------------------------------------
if [[ -n "$_INSTALL_DIR" ]]; then
  find "$_INSTALL_DIR" -type d -exec chmod 755 {} +
  echo "✅ Font installation complete. Fonts installed to '${_INSTALL_DIR}'." >&2
else
  echo "ℹ️  No new fonts to install — all requested fonts already registered." >&2
fi

if command -v fc-cache > /dev/null 2>&1; then
  echo "ℹ️  Refreshing font cache..." >&2
  fc-cache -f "$FONT_DIR" 2> /dev/null || true
fi
