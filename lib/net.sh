#!/bin/sh
# shellcheck disable=SC3043  # 'local' is not POSIX but is supported by all targeted shells (dash, ash, macOS sh)
# POSIX sh compatible — safe to source from sh and bash scripts alike.
# Do not edit _lib/ copies directly — edit lib/ instead.
#
# _net__ensure_fetch_tool and _net__ensure_ca_certs are internal helpers.
# They require ospkg.sh to be sourced first (they call ospkg__install if
# curl/wget/ca-certs are missing).

[ -n "${_NET__LIB_LOADED-}" ] && return 0
_NET__LIB_LOADED=1

_NET_FETCH_TOOL=
_NET_CA_CERTS_OK=

# _net__hdrs_with_default_ua <hdr_block> — Echo <hdr_block> unchanged if it
# already contains a User-Agent line; otherwise prepend "User-Agent: sysset".
# GitHub and some CDNs return 403 for curl's default anonymous User-Agent.
_net__hdrs_with_default_ua() {
  local _net__ua_in="$1"
  if printf '%s\n' "$_net__ua_in" | grep -qi '^user-agent:'; then
    printf '%s' "$_net__ua_in"
  else
    printf '%s%s' "User-Agent: sysset
" "$_net__ua_in"
  fi
}

# @brief net__fetch_with_retry [--retries N] [--delay N] <cmd...> — Run `<cmd>` up to N times with a delay between failures (default: 60 retries, 5s delay).
#
# Does NOT require ospkg.sh. Prefer net__fetch_url_stdout / net__fetch_url_file
# for curl/wget downloads; those handle tool detection, --compressed, and
# transient-only retries automatically. Use this function only for commands
# that are not curl/wget.
#
# Args:
#   --retries N  Maximum number of attempts (default: 60).
#   --delay N    Seconds to wait between failures (default: 5).
#   <cmd...>     Command and arguments to run.
net__fetch_with_retry() {
  local _max=60 _delay=5
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
      --)
        shift
        break
        ;;
      *) break ;;
    esac
  done
  local _i=1
  while [ "$_i" -le "$_max" ]; do
    "$@" && return 0
    [ "$_i" -lt "$_max" ] && echo "⚠️  Attempt $_i/$_max failed — retrying in ${_delay}s..." >&2 && sleep "$_delay"
    _i=$((_i + 1))
  done
  echo "⛔ Failed after $_max attempt(s)." >&2
  return 1
}

# @brief net__fetch_url_stdout <url> [--retries N] [--delay N] [--header <H>]... — Download `<url>` to stdout with retries. Auto-detects curl/wget.
#
# curl uses --retry (transient errors only: 5xx, 408, 429, connection
# failures); wget falls back to net__fetch_with_retry. Calls
# _net__ensure_fetch_tool automatically if not already initialised.
#
# Args:
#   <url>          URL to download.
#   --retries N    Maximum number of attempts (default: 60, ≈5 min at 5s).
#   --delay N      Seconds between failures (default: 5).
#   --header <H>   Request header (e.g. "Authorization: Bearer $TOKEN").
#                  May be specified multiple times.
net__fetch_url_stdout() {
  local _url="$1"
  shift
  local _max=60 _delay=5 _hdrs=''
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
      *)
        echo "⛔ net__fetch_url_stdout: unknown option: '$1'" >&2
        return 1
        ;;
    esac
  done
  _hdrs="$(_net__hdrs_with_default_ua "$_hdrs")"
  _net__ensure_fetch_tool
  if [ "$_NET_FETCH_TOOL" = "curl" ]; then
    set -- -fsSL --compressed --retry "$_max" --retry-delay "$_delay" --retry-connrefused
    while IFS= read -r _h; do
      [ -z "$_h" ] && continue
      set -- "$@" -H "$_h"
    done << _NET_HDR_EOF_
$_hdrs
_NET_HDR_EOF_
    curl "$@" "$_url"
  else
    set -- -O-
    while IFS= read -r _h; do
      [ -z "$_h" ] && continue
      set -- "$@" "--header=${_h}"
    done << _NET_HDR_EOF_
$_hdrs
_NET_HDR_EOF_
    net__fetch_with_retry --retries "$_max" --delay "$_delay" wget "$@" "$_url"
  fi
  return 0
}

# @brief net__fetch_url_file <url> <dest> [--retries N] [--delay N] [--header <H>]... — Download `<url>` to `<dest>` with retries. Auto-detects curl/wget.
#
# curl uses --retry (transient errors only: 5xx, 408, 429, connection
# failures); wget falls back to net__fetch_with_retry. Calls
# _net__ensure_fetch_tool automatically if not already initialised.
#
# Args:
#   <url>          URL to download.
#   <dest>         Destination file path.
#   --retries N    Maximum number of attempts (default: 60, ≈5 min at 5s).
#   --delay N      Seconds between failures (default: 5).
#   --header <H>   Request header (e.g. "Authorization: Bearer $TOKEN").
#                  May be specified multiple times.
net__fetch_url_file() {
  local _url="$1"
  local _dest="$2"
  shift 2
  local _max=60 _delay=5 _hdrs=''
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
      *)
        echo "⛔ net__fetch_url_file: unknown option: '$1'" >&2
        return 1
        ;;
    esac
  done
  _hdrs="$(_net__hdrs_with_default_ua "$_hdrs")"
  _net__ensure_fetch_tool
  if [ "$_NET_FETCH_TOOL" = "curl" ]; then
    set -- -fsSL --compressed --retry "$_max" --retry-delay "$_delay" --retry-connrefused
    while IFS= read -r _h; do
      [ -z "$_h" ] && continue
      set -- "$@" -H "$_h"
    done << _NET_HDR_EOF_
$_hdrs
_NET_HDR_EOF_
    curl "$@" -o "$_dest" "$_url"
  else
    set -- -O "$_dest"
    while IFS= read -r _h; do
      [ -z "$_h" ] && continue
      set -- "$@" "--header=${_h}"
    done << _NET_HDR_EOF_
$_hdrs
_NET_HDR_EOF_
    net__fetch_with_retry --retries "$_max" --delay "$_delay" wget "$@" "$_url"
  fi
  return 0
}

# _net__ensure_fetch_tool (internal)
# Sets _NET_FETCH_TOOL to "curl" or "wget"; installs curl via ospkg__install
# if neither is found.  Requires ospkg.sh to have been sourced first.
_net__ensure_fetch_tool() {
  if [ -z "${_NET_FETCH_TOOL:-}" ]; then
    if command -v curl > /dev/null 2>&1; then
      _NET_FETCH_TOOL=curl
    elif command -v wget > /dev/null 2>&1; then
      _NET_FETCH_TOOL=wget
    else
      [ -n "${_OSPKG__LIB_LOADED-}" ] || {
        echo "⛔ net.sh: ospkg.sh must be sourced before _net__ensure_fetch_tool" >&2
        return 1
      }
      echo "ℹ️  Neither curl nor wget found — installing curl." >&2
      ospkg__update
      ospkg__install_tracked "lib-net" curl
      _NET_FETCH_TOOL=curl
    fi
  fi
  _net__ensure_ca_certs
  return 0
}

# _net__ensure_ca_certs (internal)
# Ensures /etc/ssl/certs/ca-certificates.crt exists; installs ca-certificates
# via ospkg__install if not.  Requires ospkg.sh to have been sourced first.
_net__ensure_ca_certs() {
  [ -n "${_NET_CA_CERTS_OK:-}" ] && return 0
  # macOS uses its own keychain; curl/wget use it natively without a .crt file.
  [ "$(uname -s)" = "Darwin" ] && {
    _NET_CA_CERTS_OK=true
    return 0
  }
  if [ ! -s /etc/ssl/certs/ca-certificates.crt ]; then
    [ -n "${_OSPKG__LIB_LOADED-}" ] || {
      echo "⛔ net.sh: ospkg.sh must be sourced before _net__ensure_ca_certs" >&2
      return 1
    }
    echo "ℹ️  CA certificate bundle missing — installing ca-certificates." >&2
    ospkg__update
    ospkg__install_tracked "lib-net" ca-certificates
  fi
  _NET_CA_CERTS_OK=true
  return 0
}
