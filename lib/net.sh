#!/bin/sh
# POSIX sh compatible — safe to source from sh and bash scripts alike.
# Do not edit _lib/ copies directly — edit lib/ instead.
#
# net::ensure_fetch_tool and net::ensure_ca_certs require ospkg.sh to be
# sourced first (they call ospkg::install if curl/wget/ca-certs are missing).

[ -n "${_LIB_NET_LOADED-}" ] && return 0
_LIB_NET_LOADED=1

_NET_FETCH_TOOL=
_NET_CA_CERTS_OK=

# net::fetch_with_retry <max-attempts> <cmd...>
# Runs <cmd> up to <max-attempts> times with a 3-second pause between
# failures.  Does NOT require ospkg.sh.
net::fetch_with_retry() {
  local _max="$1"
  shift
  local _i=1
  while [ "$_i" -le "$_max" ]; do
    "$@" && return 0
    [ "$_i" -lt "$_max" ] && echo "⚠️  Attempt $_i/$_max failed — retrying in 3s..." >&2 && sleep 3
    _i=$((_i + 1))
  done
  echo "⛔ Failed after $_max attempt(s)." >&2
  return 1
}

# net::ensure_ca_certs
# Ensures /etc/ssl/certs/ca-certificates.crt exists; installs ca-certificates
# via ospkg::install if not.  Requires ospkg.sh to have been sourced first.
net::ensure_ca_certs() {
  [ -n "${_NET_CA_CERTS_OK:-}" ] && return 0
  # macOS uses its own keychain; curl/wget use it natively without a .crt file.
  [ "$(uname -s)" = "Darwin" ] && {
    _NET_CA_CERTS_OK=true
    return 0
  }
  if [ ! -s /etc/ssl/certs/ca-certificates.crt ]; then
    [ -n "${_LIB_OSPKG_LOADED-}" ] || {
      echo "⛔ net.sh: ospkg.sh must be sourced before net::ensure_ca_certs" >&2
      return 1
    }
    echo "ℹ️  CA certificate bundle missing — installing ca-certificates." >&2
    ospkg::update
    ospkg::install ca-certificates
  fi
  _NET_CA_CERTS_OK=true
  return 0
}

# net::ensure_fetch_tool
# Sets _NET_FETCH_TOOL to "curl" or "wget"; installs curl via ospkg::install
# if neither is found.  Requires ospkg.sh to have been sourced first.
net::ensure_fetch_tool() {
  if [ -z "${_NET_FETCH_TOOL:-}" ]; then
    if command -v curl > /dev/null 2>&1; then
      _NET_FETCH_TOOL=curl
    elif command -v wget > /dev/null 2>&1; then
      _NET_FETCH_TOOL=wget
    else
      [ -n "${_LIB_OSPKG_LOADED-}" ] || {
        echo "⛔ net.sh: ospkg.sh must be sourced before net::ensure_fetch_tool" >&2
        return 1
      }
      echo "ℹ️  Neither curl nor wget found — installing curl." >&2
      ospkg::install curl
      _NET_FETCH_TOOL=curl
    fi
  fi
  net::ensure_ca_certs
  return 0
}

# net::fetch_url_stdout <url>
# Writes URL response body to stdout using _NET_FETCH_TOOL, with retries.
# Calls net::ensure_fetch_tool automatically if not already initialised.
net::fetch_url_stdout() {
  net::ensure_fetch_tool
  if [ "$_NET_FETCH_TOOL" = "curl" ]; then
    net::fetch_with_retry 3 curl -fsSL "$1"
  else
    net::fetch_with_retry 3 wget -qO- "$1"
  fi
  return 0
}

# net::fetch_url_file <url> <dest>
# Writes URL response body to file using _NET_FETCH_TOOL, with retries.
# Calls net::ensure_fetch_tool automatically if not already initialised.
net::fetch_url_file() {
  net::ensure_fetch_tool
  if [ "$_NET_FETCH_TOOL" = "curl" ]; then
    net::fetch_with_retry 3 curl -fsSL "$1" -o "$2"
  else
    net::fetch_with_retry 3 wget -qO "$2" "$1"
  fi
  return 0
}
