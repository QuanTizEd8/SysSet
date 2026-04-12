#!/bin/sh
# POSIX sh compatible — safe to source from sh and bash scripts alike.
# Do not edit _lib/ copies directly — edit lib/ instead.
#
# Requires net.sh (and ospkg.sh) to have been sourced first.

[ -n "${_LIB_GITHUB_LOADED-}" ] && return 0
_LIB_GITHUB_LOADED=1

# github::fetch_release_json <owner/repo> [--tag <tag>] [--dest <file>]
#
# Fetches the GitHub Releases API response for a repository.
# Without --tag: fetches /releases/latest (single release object).
# With    --tag: fetches /releases/tags/<tag> (single release object).
# Without --dest: writes JSON to stdout.
# With    --dest: writes JSON to <file>.
# Respects GITHUB_TOKEN env var (Authorization: Bearer).
github::fetch_release_json() {
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
        echo "⛔ github::fetch_release_json: unknown option: '$1'" >&2
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

  net::ensure_fetch_tool
  net::ensure_ca_certs

  # Build header arguments for the detected fetch tool (curl or wget).
  if [ "$_NET_FETCH_TOOL" = "curl" ]; then
    local -a _hdr_args=(
      -H "Accept: application/vnd.github+json"
      -H "X-GitHub-Api-Version: 2022-11-28"
    )
    [ -n "${GITHUB_TOKEN:-}" ] && _hdr_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    if [ -n "$_dest" ]; then
      net::fetch_with_retry 3 curl --fail --silent --location "${_hdr_args[@]}" "$_url" -o "$_dest"
    else
      net::fetch_with_retry 3 curl --fail --silent --location "${_hdr_args[@]}" "$_url"
    fi
  else
    local -a _hdr_args=(
      --header="Accept: application/vnd.github+json"
      --header="X-GitHub-Api-Version: 2022-11-28"
    )
    [ -n "${GITHUB_TOKEN:-}" ] && _hdr_args+=(--header="Authorization: Bearer ${GITHUB_TOKEN}")
    if [ -n "$_dest" ]; then
      net::fetch_with_retry 3 wget -qO "$_dest" "${_hdr_args[@]}" "$_url"
    else
      net::fetch_with_retry 3 wget -qO- "${_hdr_args[@]}" "$_url"
    fi
  fi
  return 0
}

# github::latest_tag <owner/repo>
#
# Prints the latest release tag name for the given repository.
# Exits 1 if the API call fails or no tag can be parsed.
github::latest_tag() {
  local _repo="$1"
  local _tag
  _tag="$(github::fetch_release_json "$_repo" |
    grep '"tag_name"' | head -1 |
    sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')" || {
    echo "⛔ github::latest_tag: failed to reach GitHub API for '${_repo}'." >&2
    return 1
  }
  [ -z "$_tag" ] && {
    echo "⛔ github::latest_tag: could not parse tag_name for '${_repo}'." >&2
    return 1
  }
  echo "$_tag"
  return 0
}

# github::release_tags <owner/repo> [--per_page <n>]
#
# Prints one release tag per line (newest first) for the given repository.
# Fetches /releases?per_page=<n> (default 100).
# Useful for version-matching against a list (grep/sort/tail in the caller).
github::release_tags() {
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
        echo "⛔ github::release_tags: unknown option: '$1'" >&2
        return 1
        ;;
    esac
  done

  local _url="https://api.github.com/repos/${_repo}/releases?per_page=${_per_page}"
  net::ensure_fetch_tool
  net::ensure_ca_certs

  local _json
  local -a _hdr_args=()
  if [ "$_NET_FETCH_TOOL" = "curl" ]; then
    _hdr_args+=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
    [ -n "${GITHUB_TOKEN:-}" ] && _hdr_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    _json="$(net::fetch_with_retry 3 curl --fail --silent --location "${_hdr_args[@]}" "$_url")" || {
      echo "⛔ github::release_tags: failed to reach GitHub API for '${_repo}'." >&2
      return 1
    }
  else
    _hdr_args+=(--header="Accept: application/vnd.github+json" --header="X-GitHub-Api-Version: 2022-11-28")
    [ -n "${GITHUB_TOKEN:-}" ] && _hdr_args+=(--header="Authorization: Bearer ${GITHUB_TOKEN}")
    _json="$(net::fetch_with_retry 3 wget -qO- "${_hdr_args[@]}" "$_url")" || {
      echo "⛔ github::release_tags: failed to reach GitHub API for '${_repo}'." >&2
      return 1
    }
  fi

  [ -z "$_json" ] && {
    echo "⛔ github::release_tags: received empty response for '${_repo}'." >&2
    return 1
  }
  printf '%s\n' "$_json" |
    grep '"tag_name"' |
    sed 's/.*"tag_name": *"\([^"]*\)".*/\1/'
  return 0
}

# github::release_asset_urls <owner/repo> [--tag <tag>] [--filter <ere_pattern>]
#
# Prints one browser_download_url per line from a GitHub release.
# Without --tag: uses /releases/latest.
# With    --tag: uses /releases/tags/<tag>.
# With    --filter: applies an extended-regex grep to the URL list.
# Exits 1 if the API call fails.
github::release_asset_urls() {
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
        echo "⛔ github::release_asset_urls: unknown option: '$1'" >&2
        return 1
        ;;
    esac
  done

  local _tmpfile
  _tmpfile="$(mktemp)"

  local _fetch_args=""
  [ -n "$_tag" ] && _fetch_args="--tag ${_tag}"

  # shellcheck disable=SC2086
  github::fetch_release_json "$_repo" ${_fetch_args} --dest "$_tmpfile" || {
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
