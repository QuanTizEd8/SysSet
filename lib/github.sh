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

  local _json
  _json="$(_github__api_get "$_url")" || {
    echo "⛔ github__release_tags: failed to reach GitHub API for '${_repo}'." >&2
    return 1
  }

  [ -z "$_json" ] && {
    echo "⛔ github__release_tags: received empty response for '${_repo}'." >&2
    return 1
  }
  printf '%s\n' "$_json" |
    grep '"tag_name"' |
    sed 's/.*"tag_name": *"\([^"]*\)".*/\1/'
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
  { set +x; } 2>/dev/null

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
  [ "$_xt" = "true" ] && { set -x; } 2>/dev/null
  return "$_ec"
}
