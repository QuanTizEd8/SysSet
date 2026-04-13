#!/usr/bin/env bash
# This file must be sourced from bash (>=4.0), not sh.
# Do not edit _lib/ copies directly — edit lib/ instead.

[[ -n "${_LIB_GIT_LOADED-}" ]] && return 0
_LIB_GIT_LOADED=1

# git__clone --url <url> --dir <dir> [--branch <branch>]
# Clones <url> into <dir> with depth=1.  If <dir>/.git already exists the
# clone is skipped (idempotent).  On failure the partially-created <dir> is
# removed so a re-run does not silently skip a broken clone.
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
