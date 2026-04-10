#!/usr/bin/env bash
# This file must be sourced from bash (>=4.0), not sh.
# Do not edit _lib/ copies directly — edit .devcontainer/lib/ instead.
#
# NOTE: net::ensure_fetch_tool and net::ensure_ca_certs are added in Phase 3
# (they require ospkg.sh).  Only net::fetch_with_retry is available now.

[[ -n "${_LIB_NET_LOADED-}" ]] && return 0
_LIB_NET_LOADED=1

# net::fetch_with_retry <max-attempts> <cmd...>
# Runs <cmd> up to <max-attempts> times with a 3-second pause between
# failures.
net::fetch_with_retry() {
  local _max="$1"; shift
  local _i=1
  while [[ $_i -le $_max ]]; do
    "$@" && return 0
    [[ $_i -lt $_max ]] && echo "⚠️  Attempt $_i/$_max failed — retrying in 3s..." >&2 && sleep 3
    (( _i++ ))
  done
  echo "⛔ Failed after $_max attempt(s)." >&2
  return 1
}
