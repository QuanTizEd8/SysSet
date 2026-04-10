#!/usr/bin/env bash
# This file must be sourced from bash (>=4.0), not sh.
# Do not edit _lib/ copies directly — edit lib/ instead.

[[ -n "${_LIB_OS_LOADED-}" ]] && return 0
_LIB_OS_LOADED=1

# os::require_root
# Exits 1 with a message if the current user is not root.
os::require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo '⛔ This script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.' >&2
    exit 1
  fi
  return 0
}
