#!/usr/bin/env bash
# This file must be sourced from bash (>=4.0), not sh.
# Do not edit _lib/ copies directly — edit lib/ instead.

[[ -n "${_GIT__LIB_LOADED-}" ]] && return 0
_GIT__LIB_LOADED=1

# @brief git__clone --url <url> --dir <dir> [--branch <branch>] — Shallow clone (`--depth=1`) of `<url>` into `<dir>`. Idempotent; skips if `<dir>/.git` already exists.
#
# On failure, the partially-created <dir> is removed so that a re-run does
# not silently skip a broken clone.
#
# Args:
#   --url <url>        Repository URL to clone.
#   --dir <dir>        Local destination directory.
#   --branch <branch>  Branch or tag to check out (optional; defaults to HEAD).
git__clone() {
  local branch="" dir="" url=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --branch)
        shift
        branch="$1"
        shift
        ;;
      --dir)
        shift
        dir="$1"
        shift
        ;;
      --url)
        shift
        url="$1"
        shift
        ;;
      --*)
        echo "⛔ git__clone: unknown option '${1}'" >&2
        return 1
        ;;
      *)
        echo "⛔ git__clone: unexpected argument '${1}'" >&2
        return 1
        ;;
    esac
  done
  [ -z "${dir}" ] && {
    echo "⛔ git__clone: missing --dir" >&2
    return 1
  }
  [ -z "${url}" ] && {
    echo "⛔ git__clone: missing --url" >&2
    return 1
  }

  if [ -d "${dir}/.git" ]; then
    echo "ℹ️  '${dir}' already exists — skipping clone." >&2
    return 0
  fi

  # Auto-provision git if not yet available (idempotent if already installed).
  if ! command -v git > /dev/null 2>&1; then
    if [[ -n "${_OSPKG__LIB_LOADED-}" ]]; then
      echo "ℹ️  git not found — installing." >&2
      ospkg__detect
      ospkg__install_tracked "lib-git" git
    else
      echo "⛔ git__clone: git is not installed and ospkg.sh is not loaded." >&2
      return 1
    fi
  fi

  mkdir -p "$dir"
  local _clone_args=(--depth=1
    -c core.eol=lf
    -c core.autocrlf=false
    -c fsck.zeroPaddedFilemode=ignore
    -c fetch.fsck.zeroPaddedFilemode=ignore
    -c receive.fsck.zeroPaddedFilemode=ignore)
  [ -n "${branch}" ] && _clone_args+=(--branch "$branch")

  if ! git clone "${_clone_args[@]}" "$url" "$dir" 2>&1; then
    rm -rf "$dir" 2> /dev/null || true
    echo "⛔ git clone of '${url}' failed." >&2
    return 1
  fi
  return 0
}
