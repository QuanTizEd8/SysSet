#!/usr/bin/env bash
# This file must be sourced from bash (>=4.0), not sh.
# Do not edit _lib/ copies directly — edit lib/ instead.

[[ -n "${_LIB_LOGGING_LOADED-}" ]] && return 0
_LIB_LOGGING_LOADED=1

_LIB_LOGGING_SETUP=false

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
  _LIB_LOGGING_SETUP=true
  return 0
}

# logging::cleanup — flush temp log to $LOGFILE and restore original fds.
#
# No-op if logging::setup was never called.
# If $LOGFILE is set, appends the captured output to that file.
# Always restores the original fds and waits for the tee process to finish.
logging::cleanup() {
  [[ "${_LIB_LOGGING_SETUP-}" == true ]] || return 0
  exec 1>&3 2>&4
  wait 2> /dev/null
  exec 3>&- 4>&-
  if [ -n "${LOGFILE-}" ]; then
    echo "ℹ️ Write logs to file '$LOGFILE'" >&2
    mkdir -p "$(dirname "$LOGFILE")"
    cat "$_LOGFILE_TMP" >> "$LOGFILE"
  fi
  rm -f "${_LOGFILE_TMP-}"
  _LIB_LOGGING_SETUP=false
  return 0
}
