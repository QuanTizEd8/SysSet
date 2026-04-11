#!/bin/sh

# Bootstrap devcontainer feature `install.sh` script
#
# Ensure bash >=4 is available, then hand off to the main install script.
#
# Notes
# -----
# This file is the single source of truth for all `install.sh` scripts;
# it is distributed to each feature root by `sync-lib.sh`.
# Therefore, do not edit copies of this file directly —
# edit this one, and then run `sync-lib.sh` to propagate changes to all features.

set -e

# _find_bash4 — print the path to the first bash >=4 found; return 1 if none.
# Probes $PATH first, then well-known install prefixes so that a just-installed
# bash (e.g. Homebrew's /opt/homebrew/bin/bash) is discovered even in a shell
# session whose PATH has not yet been updated.
_find_bash4() {
  for _c in bash \
    /usr/local/bin/bash \
    /opt/homebrew/bin/bash \
    /opt/local/bin/bash \
    "$HOME/.nix-profile/bin/bash" \
    /nix/var/nix/profiles/default/bin/bash; do
    command -v "$_c" > /dev/null 2>&1 || continue
    _v=$("$_c" -c 'echo ${BASH_VERSINFO[0]}' 2> /dev/null) || continue
    [ "${_v:-0}" -ge 4 ] && {
      echo "$_c"
      return 0
    }
  done
  return 1
}

if ! _find_bash4 > /dev/null; then
  echo "🔍 bash >=4 not found — installing via system package manager." >&2
  if command -v apk > /dev/null 2>&1; then
    apk add --no-cache bash
  elif command -v apt-get > /dev/null 2>&1; then
    apt-get update && apt-get install -y --no-install-recommends bash
  elif command -v dnf > /dev/null 2>&1; then
    dnf install -y bash
  elif command -v microdnf > /dev/null 2>&1; then
    microdnf install -y bash
  elif command -v yum > /dev/null 2>&1; then
    yum install -y bash
  elif command -v zypper > /dev/null 2>&1; then
    zypper --non-interactive install bash
  elif command -v pacman > /dev/null 2>&1; then
    pacman -S --noconfirm --needed bash
  elif command -v brew > /dev/null 2>&1; then
    brew install bash
  elif command -v port > /dev/null 2>&1; then
    port install bash
  elif command -v nix-env > /dev/null 2>&1; then
    nix-env -i bash
  else
    echo "⛔ No supported package manager found to install bash >=4." >&2
    exit 1
  fi
fi

_BASH4=$(_find_bash4) || {
  echo "⛔ bash >=4 still not found after installation attempt." >&2
  exit 1
}

_SELF_DIR="$(dirname "$0")"
exec "$_BASH4" "$_SELF_DIR/scripts/install.sh" "$@"
