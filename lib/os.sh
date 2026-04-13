#!/bin/sh
# POSIX sh compatible — safe to source from sh and bash scripts alike.
# Do not edit _lib/ copies directly — edit lib/ instead.

[ -n "${_LIB_OS_LOADED-}" ] && return 0
_LIB_OS_LOADED=1

# ── Cached globals (populated lazily) ────────────────────────────────────────
_OS_KERNEL=""
_OS_ARCH=""
_OS_ID=""
_OS_ID_LIKE=""
_OS_PLATFORM=""
_OS_RELEASE_LOADED=""

# _os_load_release (private)
# Parses /etc/os-release once and caches ID and ID_LIKE.
# Uses grep/sed rather than sourcing the file to avoid env pollution.
_os_load_release() {
  [ -n "${_OS_RELEASE_LOADED-}" ] && return 0
  if [ -f /etc/os-release ]; then
    _OS_ID="$(grep -m1 '^ID=' /etc/os-release 2> /dev/null |
      sed 's/^ID=//;s/^"//;s/"$//')"
    _OS_ID_LIKE="$(grep -m1 '^ID_LIKE=' /etc/os-release 2> /dev/null |
      sed 's/^ID_LIKE=//;s/^"//;s/"$//')"
  fi
  _OS_RELEASE_LOADED=1
  return 0
}

# os__kernel — prints the kernel name (Linux or Darwin).
os__kernel() {
  [ -n "${_OS_KERNEL-}" ] || _OS_KERNEL="$(uname -s)"
  echo "$_OS_KERNEL"
  return 0
}

# os__arch — prints the CPU architecture (x86_64, aarch64, arm64, …).
os__arch() {
  [ -n "${_OS_ARCH-}" ] || _OS_ARCH="$(uname -m)"
  echo "$_OS_ARCH"
  return 0
}

# os__id — prints the ID field from /etc/os-release (e.g. ubuntu, debian, alpine).
os__id() {
  _os_load_release
  echo "${_OS_ID:-}"
  return 0
}

# os__id_like — prints ID_LIKE from /etc/os-release (space-separated family list).
os__id_like() {
  _os_load_release
  echo "${_OS_ID_LIKE:-}"
  return 0
}

# os__platform — prints a canonical platform tag.
# Returns one of: debian | alpine | rhel | macos
# 'debian' is the fallback for unrecognised Linux distros.
os__platform() {
  if [ -n "${_OS_PLATFORM-}" ]; then
    echo "$_OS_PLATFORM"
    return 0
  fi
  _os_load_release
  case "${_OS_ID:-}" in
    debian | ubuntu) _OS_PLATFORM="debian" ;;
    alpine) _OS_PLATFORM="alpine" ;;
    rhel | centos | fedora | rocky | almalinux) _OS_PLATFORM="rhel" ;;
    *)
      case "${_OS_ID_LIKE:-}" in
        *debian* | *ubuntu*) _OS_PLATFORM="debian" ;;
        *alpine*) _OS_PLATFORM="alpine" ;;
        *rhel* | *fedora* | *centos* | *"Red Hat"*) _OS_PLATFORM="rhel" ;;
        *)
          [ "$(uname -s)" = "Darwin" ] && _OS_PLATFORM="macos" || _OS_PLATFORM="debian"
          ;;
      esac
      ;;
  esac
  echo "$_OS_PLATFORM"
  return 0
}

# os__require_root
# Exits 1 with a message if the current user is not root.
os__require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo '⛔ This script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.' >&2
    exit 1
  fi
  return 0
}

# os__font_dir
# Prints the appropriate font directory for the current user.
#   root (id -u = 0): /usr/share/fonts
#   macOS non-root:   ~/Library/Fonts
#   Linux non-root:   ${XDG_DATA_HOME:-~/.local/share}/fonts
os__font_dir() {
  if [ "$(id -u)" -eq 0 ]; then
    echo "/usr/share/fonts"
  elif [ "$(os__kernel)" = "Darwin" ]; then
    echo "${HOME}/Library/Fonts"
  else
    echo "${XDG_DATA_HOME:-${HOME}/.local/share}/fonts"
  fi
  return 0
}

# os__is_container
# Returns 0 if running inside a container (Docker, Podman, Kubernetes, CI),
# 1 otherwise.  Uses the same heuristics as Homebrew's check-run-command-as-root()
# (Library/Homebrew/brew.sh) so that brew can run as root in devcontainers.
os__is_container() {
  [ -f /.dockerenv ] && return 0
  [ -f /run/.containerenv ] && return 0
  if [ -f /proc/1/cgroup ] &&
    grep -qE 'azpl_job|actions_job|docker|garden|kubepods' /proc/1/cgroup 2> /dev/null; then
    return 0
  fi
  return 1
}
