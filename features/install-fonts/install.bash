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
_download_deps__install

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

    # Extract tag_name and release id for namespace (minified JSON-safe).
    _tag_name="$(github__release_json_tag_name "$_API_RESPONSE")" || _tag_name=""
    _release_id="$(github__release_json_id "$_API_RESPONSE")" || _release_id=""
    if [[ -z "$_tag_name" || -z "$_release_id" ]]; then
      echo "⚠️  Could not parse tag_name or release id from GitHub response for '${_slug}' — setting to 0." >&2
      _tag_name="0"
      _release_id="0"
    fi
    _NS="gh/${_owner}/${_repo_name}/${_tag_name}/${_release_id}"

    # Extract all font/archive asset URLs.
    mapfile -t _ALL_ASSET_URLS < <(
      json__object_array_field_lines_stdin assets browser_download_url < "$_API_RESPONSE" |
        grep -iE '\.(ttf|otf|woff2?|tar\.xz|tar\.gz|tgz|zip)$' || true
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
