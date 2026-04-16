#!/bin/sh
# shellcheck disable=SC3043  # 'local' is not POSIX but is supported by all targeted shells (dash, ash, macOS sh)
# POSIX sh compatible — safe to source from sh and bash scripts alike.
# Do not edit _lib/ copies directly — edit lib/ instead.
#
# Requires net.sh (and ospkg.sh) to have been sourced first.

[ -n "${_GITHUB__LIB_LOADED-}" ] && return 0
_GITHUB__LIB_LOADED=1

# github__fetch_release_json <owner/repo> [--tag <tag>] [--dest <file>]
#
# Fetches the GitHub Releases API response for a repository.
# Without --tag: fetches /releases/latest (single release object).
# With    --tag: fetches /releases/tags/<tag> (single release object).
# Without --dest: writes JSON to stdout.
# With    --dest: writes JSON to <file>.
# Respects GITHUB_TOKEN env var (Authorization: Bearer).
github__fetch_release_json() {
  local _repo="$1"
  shift
  local _tag="" _dest=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tag)
        shift
        _tag="$1"
        shift
        ;;
      --dest)
        shift
        _dest="$1"
        shift
        ;;
      *)
        echo "⛔ github__fetch_release_json: unknown option: '$1'" >&2
        return 1
        ;;
    esac
  done

  local _url
  if [ -n "$_tag" ]; then
    _url="https://api.github.com/repos/${_repo}/releases/tags/${_tag}"
  else
    _url="https://api.github.com/repos/${_repo}/releases/latest"
  fi

  _github__api_get "$_url" "$_dest"
  return $?
}

# github__latest_tag <owner/repo>
#
# Prints the latest release tag name for the given repository.
# Exits 1 if the API call fails or no tag can be parsed.
github__latest_tag() {
  local _repo="$1"
  local _tag
  _tag="$(github__fetch_release_json "$_repo" |
    grep '"tag_name"' | head -1 |
    sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')" || {
    echo "⛔ github__latest_tag: failed to reach GitHub API for '${_repo}'." >&2
    return 1
  }
  [ -z "$_tag" ] && {
    echo "⛔ github__latest_tag: could not parse tag_name for '${_repo}'." >&2
    return 1
  }
  echo "$_tag"
  return 0
}

# github__release_tags <owner/repo> [--per_page <n>]
#
# Prints one release tag per line (newest first) for the given repository.
# Fetches /releases?per_page=<n> (default 100).
# Useful for version-matching against a list (grep/sort/tail in the caller).
github__release_tags() {
  local _repo="$1"
  shift
  local _per_page=100
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --per_page)
        shift
        _per_page="$1"
        shift
        ;;
      *)
        echo "⛔ github__release_tags: unknown option: '$1'" >&2
        return 1
        ;;
    esac
  done

  local _url="https://api.github.com/repos/${_repo}/releases?per_page=${_per_page}"

  _github__api_list_field "$_url" "tag_name" || {
    echo "⛔ github__release_tags: failed to reach GitHub API for '${_repo}'." >&2
    return 1
  }
  return 0
}

# github__tags <owner/repo> [--per_page <n>]
#
# Prints one tag name per line for the given repository.
# Fetches /tags?per_page=<n> (default 100).
# Unlike github__release_tags (which uses /releases), this endpoint includes
# all tags including lightweight tags not associated with a release.
github__tags() {
  local _repo="$1"
  shift
  local _per_page=100
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --per_page)
        shift
        _per_page="$1"
        shift
        ;;
      *)
        echo "⛔ github__tags: unknown option: '$1'" >&2
        return 1
        ;;
    esac
  done

  local _url="https://api.github.com/repos/${_repo}/tags?per_page=${_per_page}"

  _github__api_list_field "$_url" "name" || {
    echo "⛔ github__tags: failed to reach GitHub API for '${_repo}'." >&2
    return 1
  }
  return 0
}

# github__release_asset_urls <owner/repo> [--tag <tag>] [--filter <ere_pattern>]
#
# Prints one browser_download_url per line from a GitHub release.
# Without --tag: uses /releases/latest.
# With    --tag: uses /releases/tags/<tag>.
# With    --filter: applies an extended-regex grep to the URL list.
# Exits 1 if the API call fails.
github__release_asset_urls() {
  local _repo="$1"
  shift
  local _tag="" _filter=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tag)
        shift
        _tag="$1"
        shift
        ;;
      --filter)
        shift
        _filter="$1"
        shift
        ;;
      *)
        echo "⛔ github__release_asset_urls: unknown option: '$1'" >&2
        return 1
        ;;
    esac
  done

  local _tmpfile
  _tmpfile="$(mktemp)"

  local _fetch_args=""
  [ -n "$_tag" ] && _fetch_args="--tag ${_tag}"

  # shellcheck disable=SC2086
  github__fetch_release_json "$_repo" ${_fetch_args} --dest "$_tmpfile" || {
    rm -f "$_tmpfile"
    return 1
  }

  local _urls
  _urls="$(grep '"browser_download_url"' "$_tmpfile" |
    grep -oE 'https://[^"]+')"
  rm -f "$_tmpfile"

  if [ -n "$_filter" ]; then
    printf '%s\n' "$_urls" | grep -E "$_filter"
  else
    printf '%s\n' "$_urls"
  fi
  return 0
}

# github__pick_release_asset <owner/repo> [--tag <tag>] [--asset-regex <ERE>]
#
# Selects a single browser_download_url from a GitHub release using a cascade
# of heuristic filters based on the current host architecture and platform.
# Designed for tools that do not publish checksums or have irregular release
# naming conventions; prefer explicit URL construction with checksum
# verification when the release naming is known and stable.
#
# Filter cascade (each stage is skipped if it would reduce candidates to zero):
#   1. Negative: eliminate assets for other CPU architectures.
#   2. Negative: eliminate assets for other platforms (Windows, macOS, Android).
#   3. Negative: eliminate non-binary files (checksums, packages, certs, metadata).
#   4. Positive tiebreaker: prefer assets that explicitly name the current arch.
#   5. Positive tiebreaker: prefer statically linked / musl builds.
#
# --tag <tag>          Use a specific release tag instead of /releases/latest.
# --asset-regex <ERE>  Pre-filter applied before the cascade. If it produces
#                      exactly one URL the cascade is skipped entirely. If it
#                      produces zero URLs the function returns 1 immediately.
#
# Prints exactly one URL to stdout. Returns 1 on failure (no match or >1 remain).
github__pick_release_asset() {
  local _repo="$1"
  shift
  local _tag="" _asset_regex=""
  local _raw_arch="" _kernel=""
  local _own_arch_re="" _bad_arch_re="" _bad_platform_re="" _bad_misc_re=""
  local _tag_arg="" _urls="" _tmp="" _count=0 _re="" _n=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tag)
        shift
        _tag="$1"
        shift
        ;;
      --asset-regex)
        shift
        _asset_regex="$1"
        shift
        ;;
      *)
        echo "⛔ github__pick_release_asset: unknown option: '$1'" >&2
        return 1
        ;;
    esac
  done

  # ── Fetch all asset URLs ──────────────────────────────────────────────────
  [ -n "$_tag" ] && _tag_arg="--tag $_tag"
  # shellcheck disable=SC2086
  _urls="$(github__release_asset_urls "$_repo" ${_tag_arg})" || return 1
  if [ -z "$_urls" ]; then
    echo "⛔ github__pick_release_asset: no assets found for '${_repo}'." >&2
    return 1
  fi

  # ── Apply caller-supplied regex pre-filter ────────────────────────────────
  if [ -n "$_asset_regex" ]; then
    _tmp="$(printf '%s\n' "$_urls" | grep -E "$_asset_regex")" || true
    if [ -z "$_tmp" ]; then
      echo "⛔ github__pick_release_asset: --asset-regex '${_asset_regex}' matched no assets for '${_repo}'." >&2
      return 1
    fi
    _urls="$_tmp"
    _count="$(printf '%s\n' "$_urls" | grep -c '.')"
    if [ "$_count" -eq 1 ]; then
      printf '%s\n' "$_urls"
      return 0
    fi
  fi

  # ── Build arch regex sets ─────────────────────────────────────────────────
  _raw_arch="$(os__arch)"
  case "$_raw_arch" in
    x86_64)
      _own_arch_re='[Aa]md64|x64|x86[_-]64'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|[Aa]rm32|i[36]86|-386|_386|ppc64|[Ss]390|riscv'
      ;;
    aarch64 | arm64)
      _own_arch_re='[Aa]arch64|[Aa]rm64'
      _bad_arch_re='[Aa]md64|x86[_-]64|-x64|_x64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|i[36]86|-386|_386|ppc64|[Ss]390|riscv'
      ;;
    armv7l | armv7)
      _own_arch_re='[Aa][Rr][Mm]v7|[Aa][Rr][Mm]hf'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa]md64|x86[_-]64|-x64|_x64|[Aa][Rr][Mm]v[56]|i[36]86|-386|_386|ppc64|[Ss]390|riscv'
      ;;
    armv6l | armv6)
      _own_arch_re='[Aa][Rr][Mm]v6'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa]md64|x86[_-]64|-x64|_x64|[Aa][Rr][Mm]v[57]|[Aa][Rr][Mm]hf|i[36]86|-386|_386|ppc64|[Ss]390|riscv'
      ;;
    i386 | i686)
      _own_arch_re='i[36]86|-386|-686'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|[Aa]md64|x86[_-]64|-x64|_x64|ppc64|[Ss]390|riscv'
      ;;
    ppc64 | ppc64le)
      _own_arch_re='ppc64'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|[Aa]md64|x86[_-]64|-x64|_x64|i[36]86|-386|_386|[Ss]390|riscv'
      ;;
    s390 | s390x)
      _own_arch_re='[Ss]390'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|[Aa]md64|x86[_-]64|-x64|_x64|i[36]86|-386|_386|ppc64|riscv'
      ;;
    riscv64)
      _own_arch_re='riscv'
      _bad_arch_re='[Aa]arch64|[Aa]rm64|[Aa][Rr][Mm]v[5-7]|[Aa][Rr][Mm]hf|[Aa]md64|x86[_-]64|-x64|_x64|i[36]86|-386|_386|ppc64|[Ss]390'
      ;;
  esac

  # ── Build platform regex sets ─────────────────────────────────────────────
  _kernel="$(os__kernel)"
  case "$_kernel" in
    Linux)
      _bad_platform_re='[Ww]indows|[Ww]in32|-win-|\.msi$|\.exe$|[Mm]ac[Oo][Ss]|-osx-|_osx_|[Dd]arwin|\.dmg$|[Aa]ndroid'
      ;;
    Darwin)
      _bad_platform_re='[Ww]indows|[Ww]in32|-win-|\.msi$|\.exe$|[Ll]inux|[Aa]ndroid'
      ;;
    *)
      _bad_platform_re='[Ww]indows|[Ww]in32|\.msi$|\.exe$|[Aa]ndroid'
      ;;
  esac

  # Packages, checksums, signatures, certificates, metadata.
  _bad_misc_re='\.deb$|\.rpm$|\.pkg$|\.apk$|\.[Aa]pp[Ii]mage$|\.snap$|[Cc]hecksums|sha256|sha512|\.sha1$|\.md5$|\.sig$|\.txt$|\.pub$|\.pem$|\.crt$|\.asc$|\.json$|\.sbom$'

  # ── Apply negative filters ────────────────────────────────────────────────
  # Each filter is skipped (not applied) when it would empty the candidate list.
  for _re in "$_bad_arch_re" "$_bad_platform_re" "$_bad_misc_re"; do
    [ -z "$_re" ] && continue
    _tmp="$(printf '%s\n' "$_urls" | grep -vE "$_re")" || true
    [ -n "$_tmp" ] && _urls="$_tmp"
  done

  # ── Apply positive tiebreakers ────────────────────────────────────────────
  # Each tiebreaker is skipped when it would empty the candidate list.
  for _re in "$_own_arch_re" 'static|musl'; do
    [ -z "$_re" ] && continue
    _tmp="$(printf '%s\n' "$_urls" | grep -E "$_re")" || true
    [ -n "$_tmp" ] && _urls="$_tmp"
  done

  # ── Count survivors and return ────────────────────────────────────────────
  _count="$(printf '%s\n' "$_urls" | grep -c '.')" || _count=0
  case "$_count" in
    1)
      printf '%s\n' "$_urls"
      return 0
      ;;
    0)
      echo "⛔ github__pick_release_asset: no matching asset for '${_repo}' (arch=${_raw_arch}, kernel=${_kernel})." >&2
      return 1
      ;;
    *)
      echo "⛔ github__pick_release_asset: ${_count} ambiguous assets remain for '${_repo}'; pass --asset-regex to disambiguate:" >&2
      printf '%s\n' "$_urls" | sed 's|.*/||' | while IFS= read -r _n; do
        echo "   ${_n}" >&2
      done
      return 1
      ;;
  esac
}

# _github__api_list_field <url> <field>  (internal)
#
# Fetches a GitHub API list endpoint and extracts all values of the named JSON
# field, printing one value per line.
# Returns 1 if the API call fails or the response is empty.
_github__api_list_field() {
  local _url="$1"
  local _field="$2"
  local _json _result
  _json="$(_github__api_get "$_url")" || return 1
  [ -z "$_json" ] && return 1
  _result="$(printf '%s\n' "$_json" |
    grep "\"${_field}\"" |
    sed "s/.*\"${_field}\": *\"\([^\"]*\)\".*/\1/")"
  [ -z "$_result" ] && return 1
  printf '%s\n' "$_result"
  return 0
}

# _github__api_get <url> [<dest_file>]  (internal)
#
# Performs a GitHub API GET with standard Accept/version headers and an
# optional Authorization header from GITHUB_TOKEN.
# Suppresses xtrace around the authenticated call to prevent token leaking in
# CI logs.  Passes output to stdout or to <dest_file> when provided.
_github__api_get() {
  local _url="$1"
  local _dest="${2:-}"
  local _xt=false
  case "$-" in *x*) _xt=true ;; esac
  { set +x; } 2> /dev/null

  # Use set -- to accumulate --header args (POSIX alternative to arrays).
  set -- \
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: 2022-11-28"
  [ -n "${GITHUB_TOKEN:-}" ] && set -- "$@" --header "Authorization: Bearer ${GITHUB_TOKEN}"

  local _ec=0
  if [ -n "$_dest" ]; then
    net__fetch_url_file "$_url" "$_dest" "$@" || _ec=$?
  else
    net__fetch_url_stdout "$_url" "$@" || _ec=$?
  fi
  [ "$_xt" = "true" ] && { set -x; } 2> /dev/null
  return "$_ec"
}
