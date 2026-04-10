#!/usr/bin/env bash
# This file must be sourced from bash (>=4.0), not sh.
# Do not edit _lib/ copies directly — edit .devcontainer/lib/ instead.

[[ -n "${_LIB_LOGGING_LOADED-}" ]] && return 0
_LIB_LOGGING_LOADED=1

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# logging::setup — redirect stdout+stderr through tee into a temp file.
#
# Sets _LOGFILE_TMP in the caller's global scope.
# Saves original stdout as fd 3 and stderr as fd 4.
# Does NOT install an EXIT trap — caller is responsible.
#
# Usage:
#   logging::setup
#   trap 'logging::cleanup' EXIT
logging::setup() {
  _LOGFILE_TMP="$(mktemp)"
  exec 3>&1 4>&2
  exec > >(tee -a "$_LOGFILE_TMP" >&3) 2>&1
  return 0
}

# logging::cleanup — flush temp log to $LOGFILE and restore original fds.
#
# If $LOGFILE is unset or empty (no logging requested), just restores fds.
# Safe to call as an EXIT trap, even if logging::setup was not called
# (no-op when fds 3/4 are not open — the exec will fail silently in that case).
logging::cleanup() {
  if [ -n "${LOGFILE-}" ]; then
    exec 1>&3 2>&4
    wait 2>/dev/null
    echo "ℹ️ Write logs to file '$LOGFILE'" >&2
    mkdir -p "$(dirname "$LOGFILE")"
    cat "$_LOGFILE_TMP" >> "$LOGFILE"
    rm -f "$_LOGFILE_TMP"
  fi
  return 0
}
