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

# net__fetch_with_retry <max-attempts> <delay> <cmd...>
# Runs <cmd> up to <max-attempts> times with a <delay>-second pause between
# failures.  Does NOT require ospkg.sh.
# Prefer net__fetch_url_stdout / net__fetch_url_file for curl/wget downloads;
# those handle tool detection, --compressed, and smart transient-only retries
# automatically.  Use this function only for commands that are not curl/wget.
net__fetch_with_retry() {
  local _max="$1"
  local _delay="$2"
  shift 2
  local _i=1
  while [ "$_i" -le "$_max" ]; do
    "$@" && return 0
    [ "$_i" -lt "$_max" ] && echo "⚠️  Attempt $_i/$_max failed — retrying in ${_delay}s..." >&2 && sleep "$_delay"
    _i=$((_i + 1))
  done
  echo "⛔ Failed after $_max attempt(s)." >&2
  return 1
}

# net__fetch_url_stdout <url> [--retries N] [--delay N] [--header "Name: Value"]...
# Writes URL response body to stdout using _NET_FETCH_TOOL, with retries.
# curl: uses --retry which retries only on transient errors (5xx, 408, 429,
#   connection failures).  wget: falls back to net__fetch_with_retry.
# --retries defaults to 60 (≈5 min at 5s intervals); --delay defaults to 5s.
# Multiple --header flags may be supplied; each value is passed verbatim.
# Calls _net__ensure_fetch_tool automatically if not already initialised.
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
    net__fetch_with_retry "$_max" "$_delay" wget "$@" "$_url"
  fi
  return 0
}

# net__fetch_url_file <url> <dest> [--retries N] [--delay N] [--header "Name: Value"]...
# Writes URL response body to file using _NET_FETCH_TOOL, with retries.
# curl: uses --retry which retries only on transient errors (5xx, 408, 429,
#   connection failures).  wget: falls back to net__fetch_with_retry.
# --retries defaults to 60 (≈5 min at 5s intervals); --delay defaults to 5s.
# Multiple --header flags may be supplied; each value is passed verbatim.
# Calls _net__ensure_fetch_tool automatically if not already initialised.
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
    net__fetch_with_retry "$_max" "$_delay" wget "$@" "$_url"
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
      ospkg__install curl
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
    ospkg__install ca-certificates
  fi
  _NET_CA_CERTS_OK=true
  return 0
}
