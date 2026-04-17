#!/usr/bin/env bash
# This file must be sourced from bash (>=4.0), not sh.
# Do not edit _lib/ copies directly — edit lib/ instead.

[[ -n "${_LOGGING__LIB_LOADED-}" ]] && return 0
_LOGGING__LIB_LOADED=1

_LIB_LOGGING_SETUP=false
_SYSSET_TMPDIR=
_SYSSET_MASKED_VALUES=()

# @brief logging__setup — Redirect stdout+stderr through `tee` into a temp log file; save original fds.
#
# On first call: creates _SYSSET_TMPDIR (a process-lifetime temp dir) and
# _LOGFILE_TMP (the captured log file, inside _SYSSET_TMPDIR). Saves the
# original stdout as fd 3 and stderr as fd 4 via `exec`.
#
# Does NOT install an EXIT trap — the caller is responsible. Pair with:
#   trap 'logging__cleanup' EXIT
#
# Cleanup deletes _SYSSET_TMPDIR and all logging__tmpdir subdirectories.
# Auto-registers GITHUB_TOKEN (if set) as a masked secret.
logging__setup() {
  [[ -z "${_SYSSET_TMPDIR:-}" ]] && _SYSSET_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/sysset_XXXXXX")"
  _LOGFILE_TMP="$(mktemp "${_SYSSET_TMPDIR}/log_XXXXXX")"
  exec 3>&1 4>&2
  exec > >(tee -a "$_LOGFILE_TMP" >&3) 2>&1
  _LIB_LOGGING_SETUP=true
  # Auto-mask well-known secrets present at setup time.
  [[ -n "${GITHUB_TOKEN:-}" ]] && logging__mask_secret "$GITHUB_TOKEN"
  return 0
}

# @brief logging__mask_secret <value> — Register a secret value to be redacted when `logging__cleanup` writes to `$LOGFILE`.
#
# Args:
#   <value>  The secret string to mask. No-op if empty.
logging__mask_secret() {
  [[ -n "${1:-}" ]] && _SYSSET_MASKED_VALUES+=("$1")
  return 0
}

# @brief logging__tmpdir <name> — Return (and create if needed) a named subdirectory of `_SYSSET_TMPDIR`. Lazy-initialises `_SYSSET_TMPDIR` if needed. Idempotent.
#
# Safe to call from library code that does not control the script entry
# point, even if logging__setup has not yet been called.
#
# Args:
#   <name>  Name of the subdirectory to create under _SYSSET_TMPDIR.
#
# Stdout: absolute path to the named subdirectory.
logging__tmpdir() {
  [[ -z "${_SYSSET_TMPDIR:-}" ]] && _SYSSET_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/sysset_XXXXXX")"
  mkdir -p "${_SYSSET_TMPDIR}/${1}"
  echo "${_SYSSET_TMPDIR}/${1}"
  return 0
}

# @brief logging__cleanup — Restore original fds, flush the temp log to `$LOGFILE` if set, and delete `_SYSSET_TMPDIR`.
#
# No-op if logging__setup was never called. If $LOGFILE is set, appends the
# captured output (with any registered secrets masked) to that file. Deletes
# _SYSSET_TMPDIR (which contains _LOGFILE_TMP and any logging__tmpdir
# subdirectories) and restores the original stdout (fd 3) and stderr (fd 4).
logging__cleanup() {
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
