#!/usr/bin/env bash
# helpers.sh — Shared helper functions for install-fonts scripts.
#
# Sourced by sibling scripts; not executed directly.
# All functions are idempotent and safe to source multiple times.

# Guard against double-sourcing.
[[ -n "${_INSTALL_FONTS_HELPERS_LOADED-}" ]] && return 0
_INSTALL_FONTS_HELPERS_LOADED=1

# ---------------------------------------------------------------------------
# fetch_with_retry <max-attempts> <cmd...>
# Runs <cmd> up to <max-attempts> times with a 3-second pause between
# failures.
# ---------------------------------------------------------------------------
fetch_with_retry() {
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
