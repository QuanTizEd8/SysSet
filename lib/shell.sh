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
  _compiled="$(strings "$(command -v bash 2> /dev/null)" 2> /dev/null |
    grep -m1 -E '^/etc/(bash\.bashrc|bashrc|bash/bashrc)$' || true)"
  if [ -n "$_compiled" ]; then
    echo "$_compiled"
    return 0
  fi
  # os::platform fallback.
  case "$(os::platform)" in
    alpine)
      echo "/etc/bash/bashrc"
      return 0
      ;;
    rhel | macos)
      echo "/etc/bashrc"
      return 0
      ;;
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
  _compiled="$(strings "$(command -v zsh 2> /dev/null)" 2> /dev/null |
    grep -m1 -E '^/etc/(zsh/)?zshenv$' || true)"
  if [ -n "$_compiled" ]; then
    echo "$(dirname "$_compiled")"
    return 0
  fi
  # os::platform fallback.
  case "$(os::platform)" in
    rhel | macos)
      echo "/etc"
      return 0
      ;;
  esac
  echo "/etc/zsh"
  return 0
}

# shell::write_block --file <file> --marker <id> --content <content>
# Idempotently writes a shell block wrapped in named idempotency markers:
#   # >>> <id> >>>
#   <content>
#   # <<< <id> <<<
# Creates parent dirs and the file if needed. Updates the block content
# in-place if the marker already exists; appends otherwise.
shell::write_block() {
  local _file="" _marker="" _content=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --file)
        shift
        _file="$1"
        shift
        ;;
      --marker)
        shift
        _marker="$1"
        shift
        ;;
      --content)
        shift
        _content="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  local _begin="# >>> ${_marker} >>>"
  local _end="# <<< ${_marker} <<<"
  mkdir -p "$(dirname "$_file")"
  [ -f "$_file" ] || touch "$_file"
  if grep -qF "$_begin" "$_file"; then
    awk -v begin="$_begin" -v end="$_end" -v content="$_content" '
      $0 == begin { print; print content; found=1; next }
      found && $0 == end { print; found=0; next }
      found { next }
      { print }
    ' "$_file" > "${_file}.tmp" && mv "${_file}.tmp" "$_file"
    echo "♻️ Updated shell block '${_marker}' in '${_file}'." >&2
  else
    printf '\n%s\n%s\n%s\n' "$_begin" "$_content" "$_end" >> "$_file"
    echo "✅ Appended shell block '${_marker}' to '${_file}'." >&2
  fi
  return 0
}

# shell::sync_block --files <files> --marker <id> [--content <text>]
# For each file in the newline-separated <files> list:
#   - If --content is present: write or update the named idempotency block.
#   - If --content is absent: remove the named idempotency block if it exists.
# Skips blank lines in the file list.
shell::sync_block() {
  local _files="" _marker="" _content="" _has_content=false
  while [[ $# -gt 0 ]]; do
    case $1 in
      --files)
        shift
        _files="$1"
        shift
        ;;
      --marker)
        shift
        _marker="$1"
        shift
        ;;
      --content)
        shift
        _content="$1"
        _has_content=true
        shift
        ;;
      *) shift ;;
    esac
  done
  local _begin="# >>> ${_marker} >>>"
  local _end="# <<< ${_marker} <<<"
  while IFS= read -r _f; do
    [ -z "$_f" ] && continue
    if [ "$_has_content" = true ]; then
      shell::write_block --file "$_f" --marker "$_marker" --content "$_content"
    else
      [ -f "$_f" ] || continue
      grep -qF "$_begin" "$_f" || continue
      awk -v begin="$_begin" -v end="$_end" '
        $0 == begin { found=1; next }
        found && $0 == end { found=0; next }
        found { next }
        { print }
      ' "$_f" > "${_f}.tmp" && mv "${_f}.tmp" "$_f"
      echo "🗑 Removed shell block '${_marker}' from '${_f}'." >&2
    fi
  done <<< "$_files"
  return 0
}

# shell::user_login_file [--home <dir>]
# Prints the bash login startup file path for the given home directory.
# Returns the first existing of .bash_profile, .bash_login, .profile;
# falls back to <home>/.bash_profile if none exist yet.
# Default home: $HOME
shell::user_login_file() {
  local _home="${HOME:-}"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  local _f
  for _f in "${_home}/.bash_profile" "${_home}/.bash_login" "${_home}/.profile"; do
    [ -f "$_f" ] && {
      echo "$_f"
      return 0
    }
  done
  echo "${_home}/.bash_profile"
  return 0
}

# shell::system_path_files [--profile_d <filename>]
# Prints system-wide shell startup file paths for PATH or env variable
# injection (intended for root on Linux). One absolute path per line:
#   1. BASH_ENV file (non-login non-interactive bash — via shell::ensure_bashenv)
#   2. /etc/profile.d/<filename>  — only if --profile_d is given
#   3. <global bashrc>            — non-login interactive bash
#   4. <global zshdir>/zshenv    — all zsh invocations
shell::system_path_files() {
  local _profiled=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --profile_d)
        shift
        _profiled="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  shell::ensure_bashenv
  [ -n "$_profiled" ] && echo "/etc/profile.d/${_profiled}"
  echo "$(shell::detect_bashrc)"
  echo "$(shell::detect_zshdir)/zshenv"
  return 0
}

# shell::user_path_files [--home <dir>]
# Prints user-scoped shell startup file paths for a PATH export.
# One absolute path per line:
#   <login_file>    — bash login (.bash_profile/.bash_login/.profile)
#   <home>/.bashrc  — bash non-login interactive
#   <home>/.zshenv  — all zsh invocations (login, interactive, non-interactive)
# Default home: $HOME
shell::user_path_files() {
  local _home="${HOME:-}"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  shell::user_login_file --home "$_home"
  echo "${_home}/.bashrc"
  echo "${_home}/.zshenv"
  return 0
}

# shell::user_init_files [--home <dir>]
# Prints user-scoped shell startup file paths for a full shell initializer
# (e.g. eval "$(brew shellenv)"). One absolute path per line:
#   <login_file>       — bash login (.bash_profile/.bash_login/.profile)
#   <home>/.bashrc    — bash non-login interactive
#   <home>/.zprofile  — zsh login
#   <home>/.zshrc     — zsh interactive
# Default home: $HOME
shell::user_init_files() {
  local _home="${HOME:-}"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  shell::user_login_file --home "$_home"
  echo "${_home}/.bashrc"
  echo "${_home}/.zprofile"
  echo "${_home}/.zshrc"
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
      --theme_slug)
        shift
        slug="$1"
        shift
        ;;
      --custom_dir)
        shift
        custom_dir="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  [ -z "$slug" ] && return 0

  local _repo_name
  _repo_name="$(basename "$slug")"
  local _theme_dir="${custom_dir}/themes/${_repo_name}"
  local _theme_file
  _theme_file="$(find "$_theme_dir" -maxdepth 1 -name '*.zsh-theme' 2> /dev/null | head -1)"

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
    _env_val="$(grep -m1 '^BASH_ENV=' /etc/environment 2> /dev/null || true)"
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
