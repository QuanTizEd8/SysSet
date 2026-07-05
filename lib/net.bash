# shellcheck shell=bash
# HTTP fetch helpers with retry support using curl or wget.
#
# Auto-detects `curl` or `wget` (installs via `ospkg` if absent). All fetch
# functions support configurable retries, delay between attempts, and custom
# HTTP headers.

_NET__FETCH_TOOL=

_net__hdrs_with_default_ua() {
  # @brief _net__hdrs_with_default_ua <hdr_block> — Return `<hdr_block>` unchanged when it already contains a `User-Agent` header; otherwise prepend `User-Agent: devfeats`.
  #
  # GitHub's raw-content CDN and some other hosts return HTTP 403 for requests
  # carrying curl's default `curl/<version>` User-Agent. This helper ensures a
  # recognisable User-Agent is always present without overriding a caller-supplied
  # one.
  #
  # Args:
  #   <hdr_block>  Newline-separated list of HTTP headers (may be empty).
  #
  # Stdout: the original block if a User-Agent header is present, or the block
  #         with `User-Agent: devfeats` prepended as the first line.
  local _net__ua_in="$1"
  if printf '%s\n' "$_net__ua_in" | grep -qi '^user-agent:'; then
    printf '%s' "$_net__ua_in"
  else
    printf '%s%s' "User-Agent: devfeats
" "$_net__ua_in"
  fi
}

net__fetch_with_retry() {
  # @brief net__fetch_with_retry [--retries N] [--delay N] [--bail-on CODE] <cmd...> — Run `<cmd>` up to N times with a delay between failures (default: 60 retries, 5s delay).
  #
  # Does NOT require ospkg.bash. Prefer net__fetch_url_stdout / net__fetch_url_file
  # for curl/wget downloads; those handle tool detection, --compressed, and
  # transient-only retries automatically. Use this function only for commands
  # that are not curl/wget.
  #
  # Args:
  #   --retries N      Maximum number of attempts (default: 60, or DEVFEATS_NET_FETCH_RETRIES).
  #   --delay N        Seconds to wait between failures (default: 5, or DEVFEATS_NET_FETCH_DELAY).
  #   --bail-on CODE   If the command exits with CODE, stop immediately without
  #                    retrying (use for non-transient configuration errors).
  #   <cmd...>         Command and arguments to run.
  #
  # Returns: 0 on success, 1 after all retries exhausted.
  local _max="${DEVFEATS_NET_FETCH_RETRIES:-60}" _delay="${DEVFEATS_NET_FETCH_DELAY:-5}" _bail_on="" _xt=false
  case "$-" in *x*) _xt=true ;; esac
  { set +x; } 2> /dev/null
  while [ $# -gt 0 ]; do
    case "$1" in
      --retries)
        _max="$2"
        shift 2
        ;;
      --delay)
        _delay="$2"
        shift 2
        ;;
      --bail-on)
        _bail_on="$2"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *) break ;;
    esac
  done
  local _i=1 _rc=0
  while [ "$_i" -le "$_max" ]; do
    _rc=0
    "$@" || _rc=$?
    [ "$_rc" -eq 0 ] && {
      [[ "$_xt" == true ]] && set -x
      return 0
    }
    [ -n "$_bail_on" ] && [ "$_rc" -eq "$_bail_on" ] && {
      [[ "$_xt" == true ]] && set -x
      return "$_rc"
    }
    if [ "$_i" -lt "$_max" ]; then
      logging__warn "Attempt $_i/$_max failed — retrying in ${_delay}s..."
      sleep "$_delay"
    fi
    _i=$((_i + 1))
  done
  logging__error "Failed after $_max attempt(s)."
  [[ "$_xt" == true ]] && set -x
  return 1
}

_net__fetch() {
  # @brief _net__fetch <url> <dest> [--retries N] [--delay N] [--header <H>]... [--netrc-file <path>] — Internal: download URL via curl or wget.
  #
  # <dest> is the output file path, or empty string for stdout output.
  # curl uses --retry (transient errors, including DNS failures, but not
  # permanent failures like 404); wget falls back to net__fetch_with_retry.
  local _url="$1" _dest="$2"
  shift 2
  local _max="${DEVFEATS_NET_FETCH_RETRIES:-60}" _delay="${DEVFEATS_NET_FETCH_DELAY:-5}" _hdrs='' _netrc=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --retries)
        _max="$2"
        shift 2
        ;;
      --delay)
        _delay="$2"
        shift 2
        ;;
      --header)
        _hdrs="${_hdrs}${2}
"
        shift 2
        ;;
      --netrc-file)
        _netrc="$2"
        shift 2
        ;;
      *)
        logging__error "unknown option: '$1'"
        return 1
        ;;
    esac
  done
  _hdrs="$(_net__hdrs_with_default_ua "$_hdrs")"
  _net__ensure_fetch_tool
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to set up HTTP fetch tool."
    return "$_rc"
  }
  local _h
  if [ "$_NET__FETCH_TOOL" = "curl" ]; then
    # Force HTTP/1.1: under heavy CI network load GitHub (and other endpoints)
    # intermittently return HTTP/2 stream/framing errors (curl exit 16/92) that
    # curl's --retry does NOT treat as transient, so a single flake aborts the
    # fetch. --retry-all-errors is not an option here — it would retry the
    # deliberate 404s of the release-sidecar auto-probe 60× each. HTTP/1.1 has
    # no framing layer to stall and is plenty fast for our small fetches.
    set -- -fsSL --http1.1 --compressed --retry "$_max" --retry-delay "$_delay" --retry-connrefused
    [ -n "$_netrc" ] && set -- "$@" --netrc-file "$_netrc"
    while IFS= read -r _h; do
      [ -z "$_h" ] && continue
      set -- "$@" -H "$_h"
    done << _NET_HDR_EOF_
$_hdrs
_NET_HDR_EOF_
    if [ -n "$_dest" ]; then
      curl "$@" -o "$_dest" "$_url"
    else
      curl "$@" "$_url"
    fi
    local _rc=$?
    [ "${_rc}" -eq 0 ] && return 0
    if [ -n "$_dest" ]; then
      logging__error "failed to fetch '${_url}' to '${_dest}' with curl (exit ${_rc})."
    else
      logging__error "failed to fetch '${_url}' with curl (exit ${_rc})."
    fi
    return "${_rc}"
  elif [ "$_NET__FETCH_TOOL" = "wget" ]; then
    if [ -n "$_dest" ]; then
      set -- -O "$_dest"
    else
      set -- -O-
    fi
    [ -n "$_netrc" ] && set -- "$@" "--netrc-file=${_netrc}"
    while IFS= read -r _h; do
      [ -z "$_h" ] && continue
      set -- "$@" "--header=${_h}"
    done << _NET_HDR_EOF_
$_hdrs
_NET_HDR_EOF_
    net__fetch_with_retry --retries "$_max" --delay "$_delay" wget "$@" "$_url"
    local _rc=$?
    [ "${_rc}" -eq 0 ] && return 0
    if [ -n "$_dest" ]; then
      logging__error "failed to fetch '${_url}' to '${_dest}' with wget (exit ${_rc})."
    else
      logging__error "failed to fetch '${_url}' with wget (exit ${_rc})."
    fi
    return "${_rc}"
  fi
  logging__error "no HTTP fetch tool available (curl/wget missing after bootstrap)."
  return 1
}

net__fetch_url_stdout() {
  # @brief net__fetch_url_stdout <url> [--retries N] [--delay N] [--header <H>]... [--netrc-file <path>] — Download `<url>` to stdout with retries. Auto-detects curl/wget.
  #
  # curl uses --retry (transient errors: 5xx, 408, 429, connection failures,
  # timeouts, and DNS resolution failures — not permanent failures like 404);
  # wget falls back to net__fetch_with_retry. Calls
  # _net__ensure_fetch_tool automatically if not already initialised.
  #
  # Args:
  #   <url>                URL to download.
  #   --retries N          Maximum number of attempts (default: 60, or DEVFEATS_NET_FETCH_RETRIES).
  #   --delay N            Seconds between failures (default: 5, or DEVFEATS_NET_FETCH_DELAY).
  #   --header <H>         Request header (e.g. `Authorization: Bearer $TOKEN`); repeatable.
  #   --netrc-file <path>  Optional netrc file for HTTP authentication.
  #
  # Stdout: downloaded content.
  #
  # Returns: 0 on success, non-zero on HTTP error or timeout.
  local _url="$1"
  shift
  logging__download "Fetching '${_url}' to stdout."
  _net__fetch "$_url" "" "$@"
}

net__fetch_url_file() {
  # @brief net__fetch_url_file <url> <dest> [--retries N] [--delay N] [--header <H>]... [--netrc-file <path>] — Download `<url>` to `<dest>` with retries. Auto-detects curl/wget.
  #
  # curl uses --retry (transient errors: 5xx, 408, 429, connection failures,
  # timeouts, and DNS resolution failures — not permanent failures like 404);
  # wget falls back to net__fetch_with_retry. Calls
  # _net__ensure_fetch_tool automatically if not already initialised.
  #
  # Args:
  #   <url>                URL to download.
  #   <dest>               Destination file path.
  #   --retries N          Maximum number of attempts (default: 60, or DEVFEATS_NET_FETCH_RETRIES).
  #   --delay N            Seconds between failures (default: 5, or DEVFEATS_NET_FETCH_DELAY).
  #   --header <H>         Request header (e.g. `Authorization: Bearer $TOKEN`); repeatable.
  #   --netrc-file <path>  Optional netrc file for HTTP authentication.
  #
  # Returns: 0 on success, non-zero on HTTP error or timeout.
  local _url="$1" _dest="$2"
  shift 2
  logging__download "Fetching '${_url}' to '${_dest}'."
  _net__fetch "$_url" "$_dest" "$@"
}

_net__ensure_fetch_tool() {
  # @brief _net__ensure_fetch_tool — Detect `curl` or `wget` and set `_NET__FETCH_TOOL`; install `curl` via bootstrap if neither is found.
  #
  # Calls `bootstrap__ca_certs` after detection so every fetch that goes through
  # this helper also has a valid CA bundle. Idempotent: does nothing when
  # `_NET__FETCH_TOOL` is already set.
  #
  # snap-packaged curl (path under /snap/) runs in a sandbox that blocks most
  # outbound network connections; it is skipped in favour of wget or a bootstrapped
  # non-snap curl. See https://github.com/starship/starship/issues/5403.
  #
  # Side effects: sets `_NET__FETCH_TOOL` to `curl` or `wget`.
  # Returns: 0 on success, 1 if a required tool or CA bundle cannot be ensured.
  if [ -z "${_NET__FETCH_TOOL:-}" ]; then
    if command -v curl > /dev/null 2>&1; then
      case "$(command -v curl)" in
        /snap/*)
          logging__warn "snap-packaged curl detected at '$(command -v curl)'; skipping (sandboxed). Trying wget."
          ;;
        *)
          _NET__FETCH_TOOL=curl
          ;;
      esac
    fi
    if [ -z "${_NET__FETCH_TOOL:-}" ] && command -v wget > /dev/null 2>&1; then
      _NET__FETCH_TOOL=wget
    fi
    if [ -z "${_NET__FETCH_TOOL:-}" ]; then
      bootstrap__curl || return 1
      _NET__FETCH_TOOL=curl
    fi
  fi
  bootstrap__ca_certs
  local _rc=$?
  [[ $_rc == 0 ]] || {
    logging__error "failed to ensure CA certificates."
    return "$_rc"
  }
  return 0
}
