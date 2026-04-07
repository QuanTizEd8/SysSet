#!/usr/bin/env bash
# helpers.sh — Shared helper functions for install-shell scripts.
#
# Sourced by sibling scripts; not executed directly.
# All functions are idempotent and safe to source multiple times.

# Guard against double-sourcing.
[[ -n "${_INSTALL_SHELL_HELPERS_LOADED-}" ]] && return 0
_INSTALL_SHELL_HELPERS_LOADED=1

# ---------------------------------------------------------------------------
# git_clone --url <url> --dir <dir> [--branch <branch>]
# Clones <url> into <dir> with depth=1.  If <dir>/.git already exists the
# clone is skipped (idempotent).  On failure the partially-created <dir> is
# removed so a re-run does not silently skip a broken clone.
# ---------------------------------------------------------------------------
git_clone() {
  local branch="" dir="" url=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --branch) shift; branch="$1"; shift;;
      --dir)    shift; dir="$1";    shift;;
      --url)    shift; url="$1";    shift;;
      --*) echo "⛔ git_clone: unknown option '${1}'" >&2; return 1;;
      *)   echo "⛔ git_clone: unexpected argument '${1}'" >&2; return 1;;
    esac
  done
  [ -z "${dir}" ] && { echo "⛔ git_clone: missing --dir" >&2; return 1; }
  [ -z "${url}" ] && { echo "⛔ git_clone: missing --url" >&2; return 1; }

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
    rm -rf "$dir" 2>/dev/null || true
    echo "⛔ git clone of '${url}' failed." >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# fetch_with_retry <max-attempts> <cmd...>
# Runs <cmd> up to <max-attempts> times with a 3-second pause between
# failures.
# ---------------------------------------------------------------------------
fetch_with_retry() {
  local _max="$1"; shift
  local _i=1
  while [[ $_i -le $_max ]]; do
    "$@" && return 0
    [[ $_i -lt $_max ]] && echo "⚠️  Attempt $_i/$_max failed — retrying in 3s..." >&2 && sleep 3
    (( _i++ ))
  done
  echo "⛔ Failed after $_max attempt(s)." >&2
  return 1
}

# ---------------------------------------------------------------------------
# detect_sys_bashrc
# Prints the system-wide bashrc path for the current distro.
#   /etc/bash.bashrc  — Debian/Ubuntu, Arch, openSUSE
#   /etc/bashrc       — Fedora/RHEL/CentOS, NixOS
#   /etc/bash/bashrc  — Gentoo, Alpine, Void
# Exits non-zero if no path can be determined.
# ---------------------------------------------------------------------------
detect_sys_bashrc() {
  for _f in /etc/bash.bashrc /etc/bashrc /etc/bash/bashrc; do
    if [ -f "$_f" ]; then
      echo "$_f"
      return 0
    fi
  done
  # Fallback: inspect the compiled-in SYS_BASHRC via strings on the binary.
  local _compiled
  _compiled="$(strings "$(command -v bash)" 2>/dev/null \
    | grep -m1 -E '^/etc/(bash\.bashrc|bashrc|bash/bashrc)$' || true)"
  if [ -n "$_compiled" ]; then
    echo "$_compiled"
    return 0
  fi
  # Final fallback: create from the most common default.
  echo "/etc/bash.bashrc"
}

# ---------------------------------------------------------------------------
# detect_zsh_etcdir
# Prints the directory prefix for system-wide zsh config files.
#   /etc/zsh  — Debian/Ubuntu, Arch, Gentoo, Alpine, Void
#   /etc      — Fedora/RHEL, openSUSE, NixOS, macOS
# ---------------------------------------------------------------------------
detect_zsh_etcdir() {
  if [ -d /etc/zsh ]; then
    echo "/etc/zsh"
  else
    echo "/etc"
  fi
}

# ---------------------------------------------------------------------------
# resolve_omz_theme_value --theme_slug <slug> --custom_dir <dir>
# Given an owner/repo theme slug and the ZSH_CUSTOM directory, prints the
# ZSH_THEME value that oh-my-zsh expects (e.g. "powerlevel10k/powerlevel10k").
# Returns empty string if the theme file can't be found.
# ---------------------------------------------------------------------------
resolve_omz_theme_value() {
  local slug="" custom_dir=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --theme_slug) shift; slug="$1"; shift;;
      --custom_dir) shift; custom_dir="$1"; shift;;
      *) shift;;
    esac
  done
  [ -z "$slug" ] && return 0

  local _repo_name
  _repo_name="$(basename "$slug")"
  local _theme_dir="${custom_dir}/themes/${_repo_name}"
  local _theme_file
  _theme_file="$(find "$_theme_dir" -maxdepth 1 -name '*.zsh-theme' 2>/dev/null | head -1)"

  if [ -n "$_theme_file" ]; then
    local _stem
    _stem="$(basename "${_theme_file%.zsh-theme}")"
    echo "${_repo_name}/${_stem}"
  else
    echo "$_repo_name"
  fi
}

# ---------------------------------------------------------------------------
# plugin_names_from_slugs <comma-separated-slugs>
# Extracts the repo names (basenames) from a CSV of owner/repo slugs.
# Prints one name per line.
# ---------------------------------------------------------------------------
plugin_names_from_slugs() {
  local _slugs="$1"
  [ -z "$_slugs" ] && return 0
  local IFS=','
  local _slug
  for _slug in $_slugs; do
    _slug="${_slug// /}"
    [ -n "$_slug" ] && basename "$_slug"
  done
}

# ---------------------------------------------------------------------------
# resolve_home <username>
# Prints the home directory for the given user.
# ---------------------------------------------------------------------------
resolve_home() {
  local _user="$1"
  eval echo "~${_user}"
}
