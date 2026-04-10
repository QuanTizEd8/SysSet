#!/usr/bin/env bash
# This file must be sourced from bash (>=4.0), not sh.
# Do not edit _lib/ copies directly — edit lib/ instead.

[[ -n "${_LIB_SHELL_LOADED-}" ]] && return 0
_LIB_SHELL_LOADED=1

# shell::detect_bashrc
# Prints the system-wide bashrc path for the current distro.
#   /etc/bash.bashrc  — Debian/Ubuntu, Arch, openSUSE
#   /etc/bashrc       — Fedora/RHEL/CentOS, NixOS
#   /etc/bash/bashrc  — Gentoo, Alpine, Void
# Falls back to strings-binary probe, then /etc/bash.bashrc.
shell::detect_bashrc() {
  for _f in /etc/bash.bashrc /etc/bashrc /etc/bash/bashrc; do
    if [ -f "$_f" ]; then
      echo "$_f"
      return 0
    fi
  done
  local _compiled
  _compiled="$(strings "$(command -v bash)" 2>/dev/null \
    | grep -m1 -E '^/etc/(bash\.bashrc|bashrc|bash/bashrc)$' || true)"
  if [ -n "$_compiled" ]; then
    echo "$_compiled"
    return 0
  fi
  echo "/etc/bash.bashrc"
  return 0
}

# shell::detect_zshdir
# Prints the directory prefix for system-wide zsh config files.
#   /etc/zsh  — Debian/Ubuntu, Arch, Gentoo, Alpine, Void
#   /etc      — Fedora/RHEL, openSUSE, NixOS, macOS
shell::detect_zshdir() {
  if [ -d /etc/zsh ]; then
    echo "/etc/zsh"
  else
    echo "/etc"
  fi
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
