#!/bin/sh

# Feature entry point.
#
# Ensure bash >=4.4 is available, then hand off to the main install script.
# POSIX-phase messages buffer via lib/logging.sh; install.bash replays them at
# logging__setup once options (including log_level / log_file) are final.
#
# Notes
# -----
# This file is the single source of truth for all `install.sh` scripts;
# it is distributed to each feature root.
# Therefore, do not edit copies of this file directly —
# edit this one, and then run `scripts/sync-src.sh` to propagate changes to all features.

set -e

# shellcheck source=lib/logging.sh
. "$(dirname "$0")/lib/logging.sh"
# shellcheck source=lib/posix.sh
. "$(dirname "$0")/lib/posix.sh"
logging__pending_init

_bash_is_44() {
  # Return 0 if bash >=4.4. Without argument: test the current shell by parsing
  # $BASH_VERSION (only call when BASH_VERSION is set). With argument: spawn the
  # given binary as a subshell and evaluate BASH_VERSINFO directly — no string
  # join/split needed.
  if [ -z "${1:-}" ]; then
    _vmaj="${BASH_VERSION%%.*}"
    _vmin="${BASH_VERSION#*.}"
    _vmin="${_vmin%%.*}"
    [ "${_vmaj:-0}" -gt 4 ] || { [ "${_vmaj:-0}" -eq 4 ] && [ "${_vmin:-0}" -ge 4 ]; }
  else
    # shellcheck disable=SC2016
    "$1" -c '[ "${BASH_VERSINFO[0]}" -gt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 4 ]; }' 2> /dev/null
  fi
}

_ensure_bash4() {
  # Case 1: already running in a compatible bash (invoked as 'bash install.sh').
  # $BASH is the path bash used to start itself; resolve it to absolute before
  # any cd can change CWD.  Absolute paths are used directly; relative paths
  # (e.g. ./bash install.sh) are resolved via cd+pwd; bare names should not
  # occur in practice (bash resolves its own argv[0] through PATH), but the
  # -x guard handles the degenerate case safely.
  #
  # Guard: skip this case when bash was invoked as 'sh' (e.g. on openSUSE,
  # /bin/sh is a bash symlink and $BASH is /usr/bin/sh).  Exec'ing that path
  # would run install.bash in POSIX mode, disabling process substitution
  # (< <(...)) and causing a syntax error.  Fall through to Case 2 instead,
  # which resolves the proper 'bash'-named binary.
  _BASH_BIN=""
  if [ -n "${BASH_VERSION:-}" ] && _bash_is_44; then
    case "${BASH:-}" in
      /*)
        _BASH_BIN="$BASH"
        ;;
      ?*/*)
        _BASH_BIN="$(cd "$(dirname "$BASH")" 2> /dev/null && pwd)/$(basename "$BASH")"
        [ -x "$_BASH_BIN" ] || _BASH_BIN=""
        ;;
    esac
    # Reject if the resolved binary's basename isn't 'bash' — a 'sh'-named
    # binary runs in POSIX mode regardless of the version.
    [ "${_BASH_BIN##*/}" = "bash" ] || _BASH_BIN=""
  fi

  # Case 2: compatible bash already on the system.
  if [ -z "$_BASH_BIN" ]; then
    _BASH_BIN="$(_find_bash4 2> /dev/null)" || _BASH_BIN=""
  fi

  # Case 3: all compile prerequisites available — build from source.
  if [ -z "$_BASH_BIN" ] && _can_compile; then
    _BASH_BIN="$(_compile_bash)" || _BASH_BIN=""
    [ -n "$_BASH_BIN" ] && export _BASH_INSTALLED_INTERNALLY=1
  fi

  # Case 4: use the OS package manager to install bash directly.
  if [ -z "$_BASH_BIN" ]; then
    _pm="$(_detect_pm 2> /dev/null)" || _pm=""
    if [ -z "$_pm" ]; then
      logging__error "bash >=4.4 unavailable: no compatible bash, build tools, or package manager found."
      exit 1
    fi
    if _pm_needs_root "$_pm" && ! _can_sudo; then
      logging__error "bash >=4.4 unavailable: '${_pm}' requires root or passwordless sudo, neither available."
      exit 1
    fi
    _BASH_BIN="$(_install_bash_pkg "$_pm")" || _BASH_BIN=""
    [ -n "$_BASH_BIN" ] && export _BASH_INSTALLED_BY_PM="$_pm"
  fi

  if [ -z "$_BASH_BIN" ]; then
    logging__error "bash >=4.4 could not be obtained."
    exit 1
  fi

  export _BASH_BIN

  # Scrub every helper function and all intermediate variables from the
  # environment before exec so install.bash inherits a clean namespace.
  # _BASH_BIN, _BASH_INSTALLED_INTERNALLY, and _BASH_INSTALLED_BY_PM are
  # intentionally kept — install.bash reads them in __init__ / __exit__.
  unset -f _bash_is_44 _have _can_sudo _run_privileged _find_bash4 \
    _can_compile _compile_bash _detect_pm _pm_needs_root \
    _install_bash_pkg _ensure_bash4 posix__bootstrap_xcode posix__install_bash_from_source
  unset _vmaj _vmin _pm _c _b _v _ipm _xcode_pkg _BASH_VER _BASH_URL _tmpdir _bash_bin _dest_dir
}

_find_bash4() {
  # Print the path to the first bash >=4.4 found; return 1 if none.
  #
  # Probes $PATH first, then well-known install prefixes so that a just-installed
  # bash (e.g. Homebrew's /opt/homebrew/bin/bash) is discovered even in a shell
  # session whose PATH has not yet been updated.  Also probes the user-local bin
  # where a previously compiled bootstrap bash may have been kept.

  for _c in bash \
    /usr/local/bin/bash \
    /opt/homebrew/bin/bash \
    /opt/local/bin/bash \
    "${HOME:-/root}/.local/bin/bash" \
    "${HOME:-/root}/.nix-profile/bin/bash" \
    /nix/var/nix/profiles/default/bin/bash; do
    command -v "$_c" > /dev/null 2>&1 || continue
    _bash_is_44 "$_c" || continue
    command -v "$_c"
    return 0
  done
  return 1
}

_compile_bash() {
  # Compile bash 5.3 from GNU source and install to $HOME/.local/bin/bash.
  #
  # Prints the installed binary path to stdout. Status messages buffer via lib/logging.sh.
  # The caller exports _BASH_BIN and _BASH_INSTALLED_INTERNALLY so install.bash
  # can register it for cleanup via install__track_internal_path / ospkg__cleanup_resources,
  # respecting KEEP_BUILD_DEPS.
  _BASH_VER="5.3"
  logging__inspect "bash >=4.4 not found — compiling bash ${_BASH_VER} from source."
  posix__install_bash_from_source "${HOME:-/root}/.local" "${_BASH_VER}"
}

_install_bash_pkg() {
  _ipm="$1"
  logging__install "Installing bash via ${_ipm}..."
  case "$_ipm" in
    apk) posix__run_with_retry apk install _run_privileged apk add --no-cache bash >&2 || {
      logging__error "Failed to install bash via apk."
      return 1
    } ;;
    apt-get)
      export DEBIAN_FRONTEND=noninteractive
      posix__run_with_retry apt-get update _run_privileged apt-get update >&2 || {
        logging__error "Failed to update package index via apt-get."
        return 1
      }
      posix__run_with_retry apt-get install _run_privileged apt-get install -y --no-install-recommends bash >&2 || {
        logging__error "Failed to install bash via apt-get."
        return 1
      }
      ;;
    dnf) posix__run_with_retry dnf install _run_privileged dnf install -y bash >&2 || {
      logging__error "Failed to install bash via dnf."
      return 1
    } ;;
    microdnf) posix__run_with_retry microdnf install _run_privileged microdnf install -y bash >&2 || {
      logging__error "Failed to install bash via microdnf."
      return 1
    } ;;
    yum) posix__run_with_retry yum install _run_privileged yum install -y bash >&2 || {
      logging__error "Failed to install bash via yum."
      return 1
    } ;;
    zypper) posix__run_with_retry zypper install _run_privileged zypper --non-interactive install bash >&2 || {
      logging__error "Failed to install bash via zypper."
      return 1
    } ;;
    pacman) posix__run_with_retry pacman install _run_privileged pacman -S --noconfirm --needed bash >&2 || {
      logging__error "Failed to install bash via pacman."
      return 1
    } ;;
    brew) posix__run_with_retry brew install brew install bash >&2 || {
      logging__error "Failed to install bash via brew."
      return 1
    } ;;
    nix-env) posix__run_with_retry nix-env install nix-env -iA nixpkgs.bash >&2 || {
      logging__error "Failed to install bash via nix-env."
      return 1
    } ;;
    port) posix__run_with_retry port install _run_privileged port install bash >&2 || {
      logging__error "Failed to install bash via port."
      return 1
    } ;;
    *)
      logging__error "Unknown package manager '${_ipm}'."
      return 1
      ;;
  esac
  # Locate the newly installed bash — all destinations are already in _find_bash4's probe list.
  _b="$(_find_bash4 2> /dev/null)" || {
    logging__error "bash >=4.4 not found after installing via ${_ipm}."
    return 1
  }
  echo "$_b"
}

_have() {
  command -v "$1" > /dev/null 2>&1
}

_can_sudo() {
  [ "$(id -u)" = "0" ] && return 0
  _have sudo && sudo -n true > /dev/null 2>&1
}

_run_privileged() {
  if [ "$(id -u)" = "0" ]; then
    "$@"
  else
    sudo -n "$@"
  fi
}

_can_compile() {
  # On Darwin: make+cc may need Xcode CLT (installable when _can_sudo).
  # On Linux: all tools must already be present — no PM install of build tools.
  _have tar || return 1
  { _have curl || _have wget; } || return 1
  if [ "$(uname -s)" = "Darwin" ]; then
    { _have make && _have cc; } || _can_sudo || return 1
    return 0
  fi
  _have make || return 1
  { _have cc || _have gcc; } || return 1
  return 0
}

_detect_pm() {
  # Print the name of the first available package manager; return 1 if none.
  if [ "$(uname -s)" = "Darwin" ]; then
    for _pm in brew port nix-env; do
      _have "$_pm" && {
        echo "$_pm"
        return 0
      }
    done
    return 1
  fi
  for _pm in apt-get apk dnf microdnf yum zypper pacman brew nix-env port; do
    _have "$_pm" && {
      echo "$_pm"
      return 0
    }
  done
  return 1
}

_pm_needs_root() {
  case "$1" in
    brew | nix-env) return 1 ;;
    *) return 0 ;;
  esac
}

logging__launch "Starting install.sh script '$(basename "$0")'"
_ensure_bash4
logging__pending_handoff
exec "$_BASH_BIN" "$(dirname "$0")/install.bash" "$@"
