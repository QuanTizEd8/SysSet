#!/usr/bin/env bash
# This file must be sourced from bash (>=4.0), not sh.
# Do not edit _lib/ copies directly — edit lib/ instead.

[[ -n "${_LIB_LOGGING_LOADED-}" ]] && return 0
_LIB_LOGGING_LOADED=1

_LIB_LOGGING_SETUP=false
_SYSSET_TMPDIR=
_SYSSET_MASKED_VALUES=()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# logging::setup — redirect stdout+stderr through tee into a temp file.
#
# Creates _SYSSET_TMPDIR (a process-lifetime temp directory) on first call.
# Creates _LOGFILE_TMP (the captured log file, inside _SYSSET_TMPDIR).
# Saves original stdout as fd 3 and stderr as fd 4.
# Does NOT install an EXIT trap — caller is responsible.
# logging::cleanup (called from the EXIT trap) deletes _SYSSET_TMPDIR and
# everything inside it, including all logging::tmpdir subdirectories.
# Auto-registers GITHUB_TOKEN (if set) as a masked secret.
#
# Usage:
#   logging::setup
#   trap 'logging::cleanup' EXIT
logging::setup() {
  [[ -z "${_SYSSET_TMPDIR:-}" ]] && _SYSSET_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/sysset_XXXXXX")"
  _LOGFILE_TMP="$(mktemp "${_SYSSET_TMPDIR}/log_XXXXXX")"
  exec 3>&1 4>&2
  exec > >(tee -a "$_LOGFILE_TMP" >&3) 2>&1
  _LIB_LOGGING_SETUP=true
  # Auto-mask well-known secrets present at setup time.
  [[ -n "${GITHUB_TOKEN:-}" ]] && logging::mask_secret "$GITHUB_TOKEN"
  return 0
}

# logging::mask_secret <value> — register a secret value to be redacted when
# logging::cleanup writes to $LOGFILE.  Call once per secret after logging::setup.
logging::mask_secret() {
  [[ -n "${1:-}" ]] && _SYSSET_MASKED_VALUES+=("$1")
  return 0
}

# logging::tmpdir <name> — return (and create if needed) a named subdirectory
# of _SYSSET_TMPDIR.  Idempotent.
# Lazy-initialises _SYSSET_TMPDIR if logging::setup has not yet been called,
# so this is safe to call from library code that does not control the script
# entry point.
logging::tmpdir() {
  [[ -z "${_SYSSET_TMPDIR:-}" ]] && _SYSSET_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/sysset_XXXXXX")"
  mkdir -p "${_SYSSET_TMPDIR}/${1}"
  echo "${_SYSSET_TMPDIR}/${1}"
  return 0
}

# logging::cleanup — flush temp log to $LOGFILE, delete _SYSSET_TMPDIR, and
# restore original fds.
#
# No-op if logging::setup was never called.
# If $LOGFILE is set, appends the captured output to that file.
# Deletes _SYSSET_TMPDIR (which contains _LOGFILE_TMP and any
# logging::tmpdir subdirectories) and restores the original fds.
logging::cleanup() {
  [[ "${_LIB_LOGGING_SETUP-}" == true ]] || return 0
  exec 1>&3 2>&4
  wait 2> /dev/null
  exec 3>&- 4>&-
  if [ -n "${LOGFILE-}" ]; then
    echo "ℹ️ Write logs to file '$LOGFILE'" >&2
    mkdir -p "$(dirname "$LOGFILE")"
    if [[ ${#_SYSSET_MASKED_VALUES[@]} -gt 0 ]]; then
      local _log _v
      _log="$(cat "$_LOGFILE_TMP")"
      for _v in "${_SYSSET_MASKED_VALUES[@]}"; do
        [[ -n "$_v" ]] && _log="${_log//"$_v"/***}"
      done
      printf '%s' "$_log" >> "$LOGFILE"
    else
      cat "$_LOGFILE_TMP" >> "$LOGFILE"
    fi
  fi
  rm -rf "${_SYSSET_TMPDIR-}"
  _SYSSET_TMPDIR=
  _SYSSET_MASKED_VALUES=()
  _LIB_LOGGING_SETUP=false
  return 0
}
