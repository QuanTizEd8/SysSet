#!/usr/bin/env bash
# This file must be sourced from bash (>=4.0), not sh.
# Do not edit _lib/ copies directly — edit lib/ instead.

[[ -n "${_LIB_SHELL_LOADED-}" ]] && return 0
_LIB_SHELL_LOADED=1

_SHELL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SHELL_LIB_DIR/os.sh"

# shell::detect_bashrc
# Prints the system-wide bashrc path for the current distro.
#   /etc/bash.bashrc  — Debian/Ubuntu, Arch, openSUSE
#   /etc/bashrc       — Fedora/RHEL/CentOS, NixOS, macOS
#   /etc/bash/bashrc  — Alpine, Gentoo, Void
# Detection order: (1) strings-probe the bash binary (most accurate — bash
# itself reports the file it was compiled with); (2) os-release platform IDs.
# Never uses file-existence checks — a file at the wrong path for this distro
# won't be sourced by any shell, so writing to it would have no effect.
shell::detect_bashrc() {
  # Ask bash which RC file it was compiled with — most accurate.
  local _compiled
  _compiled="$(strings "$(command -v bash 2>/dev/null)" 2>/dev/null \
    | grep -m1 -E '^/etc/(bash\.bashrc|bashrc|bash/bashrc)$' || true)"
  if [ -n "$_compiled" ]; then
    echo "$_compiled"
    return 0
  fi
  # os::platform fallback.
  case "$(os::platform)" in
    alpine)      echo "/etc/bash/bashrc"; return 0 ;;
    rhel|macos)  echo "/etc/bashrc";      return 0 ;;
  esac
  echo "/etc/bash.bashrc"
  return 0
}

# shell::detect_zshdir
# Prints the directory prefix for system-wide zsh config files.
#   /etc/zsh  — Debian/Ubuntu, Arch, Alpine, Gentoo, Void
#   /etc      — Fedora/RHEL, openSUSE, NixOS, macOS
# Detection order: (1) strings-probe the zsh binary (zsh compiles in the path
# of its global zshenv); (2) os-release platform IDs.
# Never uses directory-existence checks — a directory at the wrong path for
# this distro won't be used by the shell anyway.
shell::detect_zshdir() {
  # Ask zsh which global zshenv path it was compiled with.
  local _compiled
  _compiled="$(strings "$(command -v zsh 2>/dev/null)" 2>/dev/null \
    | grep -m1 -E '^/etc/(zsh/)?zshenv$' || true)"
  if [ -n "$_compiled" ]; then
    echo "$(dirname "$_compiled")"
    return 0
  fi
  # os::platform fallback.
  case "$(os::platform)" in
    rhel|macos) echo "/etc"; return 0 ;;
  esac
  echo "/etc/zsh"
  return 0
}

# shell::resolve_omz_theme --theme_slug <slug> --custom_dir <dir>
# Given an owner/repo theme slug and the ZSH_CUSTOM directory, prints the
# ZSH_THEME value that oh-my-zsh expects (e.g. "powerlevel10k/powerlevel10k").
# Prints the repo name alone if the theme file can't be found.
shell::resolve_omz_theme() {
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
  return 0
}

# shell::plugin_names_from_slugs <comma-separated-slugs>
# Extracts the repo names (basenames) from a CSV of owner/repo slugs.
# Prints one name per line.
shell::plugin_names_from_slugs() {
  local _slugs="$1"
  [ -z "$_slugs" ] && return 0
  local IFS=','
  local _slug
  for _slug in $_slugs; do
    _slug="${_slug// /}"
    [ -n "$_slug" ] && basename "$_slug"
  done
  return 0
}

# shell::resolve_home <username>
# Prints the home directory for the given user.
shell::resolve_home() {
  local _user="$1"
  eval echo "~${_user}"
  return 0
}

# shell::ensure_bashenv
# Detects or creates the system-wide BASH_ENV file and registers it in
# /etc/environment. Prints the absolute path to the file.
# Detection priority:
#   1. $BASH_ENV environment variable — already set, reuse as-is.
#   2. BASH_ENV= entry in /etc/environment — already registered, reuse.
#   3. Create <bashrc_dir>/bashenv, register BASH_ENV="<path>" in /etc/environment.
# Callers are responsible for writing content to the returned path.
shell::ensure_bashenv() {
  # 1. Live environment variable
  if [ -n "${BASH_ENV:-}" ]; then
    echo "ℹ️ BASH_ENV already set to '${BASH_ENV}'; reusing." >&2
    echo "$BASH_ENV"
    return 0
  fi
  # 2. Existing /etc/environment entry
  if [ -f /etc/environment ]; then
    local _env_val
    _env_val="$(grep -m1 '^BASH_ENV=' /etc/environment 2>/dev/null || true)"
    if [ -n "$_env_val" ]; then
      _env_val="${_env_val#BASH_ENV=}"
      _env_val="${_env_val#[\"\']}"
      _env_val="${_env_val%[\"\']}"
      echo "ℹ️ Found BASH_ENV='${_env_val}' in /etc/environment; reusing." >&2
      echo "$_env_val"
      return 0
    fi
  fi
  # 3. Create new bashenv file and register in /etc/environment
  local _bashrc
  _bashrc="$(shell::detect_bashrc)"
  local _bashenv_dir
  _bashenv_dir="$(dirname "$_bashrc")"
  local _bashenv_path="${_bashenv_dir}/bashenv"
  echo "ℹ️ No BASH_ENV found; creating '${_bashenv_path}' and registering in /etc/environment." >&2
  mkdir -p "$_bashenv_dir"
  [ -f "$_bashenv_path" ] || touch "$_bashenv_path"
  printf 'BASH_ENV="%s"\n' "$_bashenv_path" >> /etc/environment
  echo "$_bashenv_path"
  return 0
}
