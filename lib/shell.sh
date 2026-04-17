#!/usr/bin/env bash
# This file must be sourced from bash (>=4.0), not sh.
# Do not edit _lib/ copies directly — edit lib/ instead.

[[ -n "${_SHELL__LIB_LOADED-}" ]] && return 0
_SHELL__LIB_LOADED=1

_SHELL__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/os.sh
. "$_SHELL__LIB_DIR/os.sh"

# shell__detect_bashrc
# Prints the system-wide bashrc path for the current distro.
#   /etc/bash.bashrc  — Debian/Ubuntu, Arch, openSUSE
#   /etc/bashrc       — Fedora/RHEL/CentOS, NixOS, macOS
#   /etc/bash/bashrc  — Alpine, Gentoo, Void
# Detection order: (1) strings-probe the bash binary (most accurate — bash
# itself reports the file it was compiled with); (2) os-release platform IDs.
# Never uses file-existence checks — a file at the wrong path for this distro
# won't be sourced by any shell, so writing to it would have no effect.
shell__detect_bashrc() {
  # Ask bash which RC file it was compiled with — most accurate.
  local _compiled
  _compiled="$(strings "$(command -v bash 2> /dev/null)" 2> /dev/null |
    grep -m1 -E '^/etc/(bash\.bashrc|bashrc|bash/bashrc)$' || true)"
  if [ -n "$_compiled" ]; then
    echo "$_compiled"
    return 0
  fi
  # os__platform fallback.
  case "$(os__platform)" in
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

# shell__detect_zshdir
# Prints the directory prefix for system-wide zsh config files.
#   /etc/zsh  — Debian/Ubuntu, Arch, Alpine, Gentoo, Void
#   /etc      — Fedora/RHEL, openSUSE, NixOS, macOS
# Detection order: (1) strings-probe the zsh binary (zsh compiles in the path
# of its global zshenv); (2) os-release platform IDs.
# Never uses directory-existence checks — a directory at the wrong path for
# this distro won't be used by the shell anyway.
shell__detect_zshdir() {
  # Ask zsh which global zshenv path it was compiled with.
  local _compiled
  _compiled="$(strings "$(command -v zsh 2> /dev/null)" 2> /dev/null |
    grep -m1 -E '^/etc/(zsh/)?zshenv$' || true)"
  if [ -n "$_compiled" ]; then
    dirname "$_compiled"
    return 0
  fi
  # os__platform fallback.
  case "$(os__platform)" in
    rhel | macos)
      echo "/etc"
      return 0
      ;;
  esac
  echo "/etc/zsh"
  return 0
}

# shell__write_block --file <file> --marker <id> --content <content>
# Idempotently writes a shell block wrapped in named idempotency markers:
#   # >>> <id> >>>
#   <content>
#   # <<< <id> <<<
# Creates parent dirs and the file if needed. Updates the block content
# in-place if the marker already exists; appends otherwise.
shell__write_block() {
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

# shell__sync_block --files <files> --marker <id> [--content <text>]
# For each file in the newline-separated <files> list:
#   - If --content is present: write or update the named idempotency block.
#   - If --content is absent: remove the named idempotency block if it exists.
# Skips blank lines in the file list.
shell__sync_block() {
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
      shell__write_block --file "$_f" --marker "$_marker" --content "$_content"
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

# shell__user_login_file [--home <dir>]
# Prints the bash login startup file path for the given home directory.
# Returns the first existing of .bash_profile, .bash_login, .profile;
# falls back to <home>/.bash_profile if none exist yet.
# Default home: $HOME
shell__user_login_file() {
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

# shell__system_path_files [--profile_d <filename>]
# Prints system-wide shell startup file paths for PATH or env variable
# injection (intended for root on Linux). One absolute path per line:
#   1. BASH_ENV file (non-login non-interactive bash — via shell__ensure_bashenv)
#   2. /etc/profile.d/<filename>  — only if --profile_d is given
#   3. <global bashrc>            — non-login interactive bash
#   4. <global zshdir>/zshenv    — all zsh invocations
shell__system_path_files() {
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
  shell__ensure_bashenv
  [ -n "$_profiled" ] && echo "/etc/profile.d/${_profiled}"
  shell__detect_bashrc
  echo "$(shell__detect_zshdir)/zshenv"
  return 0
}

# shell__detect_zdotdir [--home <dir>]
# Prints the ZDOTDIR for the given home directory.
# Detection order:
#   1. If <home> matches $HOME and $ZDOTDIR is set → use $ZDOTDIR directly
#      (we are the target user, the value is live in the environment).
#   2. Parse ZDOTDIR= assignments from the system zshenv and <home>/.zshenv.
#      Substitutes $HOME, ${HOME}, ~, $XDG_CONFIG_HOME, ${XDG_CONFIG_HOME}.
#      If the result still contains unresolvable variables ($...), falls back.
#   3. Falls back to <home>.
shell__detect_zdotdir() {
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

  # Tier 1: live environment — we ARE the target user.
  if [[ "$_home" == "${HOME:-}" && -n "${ZDOTDIR:-}" ]]; then
    echo "$ZDOTDIR"
    return 0
  fi

  # Tier 2: parse ZDOTDIR= from zshenv files.
  local _zshenv_files=""
  local _sys_zshenv
  _sys_zshenv="$(shell__detect_zshdir)/zshenv"
  [[ -f "$_sys_zshenv" ]] && _zshenv_files="$_sys_zshenv"
  [[ -f "${_home}/.zshenv" ]] && _zshenv_files="${_zshenv_files:+${_zshenv_files}
}${_home}/.zshenv"

  if [[ -n "$_zshenv_files" ]]; then
    local _val=""
    while IFS= read -r _f; do
      [[ -z "$_f" ]] && continue
      # Match last ZDOTDIR= assignment (last wins, like shell evaluation).
      # Strips optional 'export ', quotes, and trailing comments.
      # Uses [[:space:]] instead of \s for macOS sed compatibility.
      _val="$(grep -E '^[[:space:]]*(export[[:space:]]+)?ZDOTDIR=' "$_f" 2> /dev/null | tail -1 |
        sed -E 's/^[[:space:]]*(export[[:space:]]+)?ZDOTDIR=//; s/^["'"'"']//; s/["'"'"'][[:space:]]*(#.*)?$//; s/[[:space:]]*#.*//')" || true
      # Keep iterating — user .zshenv overrides system zshenv.
    done <<< "$_zshenv_files"
    if [[ -n "$_val" ]]; then
      # Substitute known variables with concrete values.
      local _xdg="${XDG_CONFIG_HOME:-${_home}/.config}"
      _val="${_val//\$\{XDG_CONFIG_HOME\}/$_xdg}"
      _val="${_val//\$XDG_CONFIG_HOME/$_xdg}"
      _val="${_val//\$\{HOME\}/$_home}"
      _val="${_val//\$HOME/$_home}"
      _val="${_val/#\~/$_home}"
      # If unresolvable variables remain, fall back to <home>.
      if [[ "$_val" == *'$'* ]]; then
        echo "$_home"
        return 0
      fi
      echo "$_val"
      return 0
    fi
  fi

  # Tier 3: fallback.
  echo "$_home"
  return 0
}

# shell__user_path_files [--home <dir>] [--zdotdir <dir>]
# Prints user-scoped shell startup file paths for a PATH export.
# One absolute path per line:
#   <login_file>      — bash login (.bash_profile/.bash_login/.profile)
#   <home>/.bashrc    — bash non-login interactive
#   <zdotdir>/.zshenv — all zsh invocations (login, interactive, non-interactive)
# Default home: $HOME
# Default zdotdir: auto-detected via shell__detect_zdotdir
shell__user_path_files() {
  local _home="${HOME:-}" _zdotdir=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      --zdotdir)
        shift
        _zdotdir="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  [[ -z "$_zdotdir" ]] && _zdotdir="$(shell__detect_zdotdir --home "$_home")"
  shell__user_login_file --home "$_home"
  echo "${_home}/.bashrc"
  echo "${_zdotdir}/.zshenv"
  return 0
}

# shell__user_init_files [--home <dir>] [--zdotdir <dir>]
# Prints user-scoped shell startup file paths for a full shell initializer
# (e.g. eval "$(brew shellenv)"). One absolute path per line:
#   <login_file>        — bash login (.bash_profile/.bash_login/.profile)
#   <home>/.bashrc      — bash non-login interactive
#   <zdotdir>/.zprofile — zsh login
#   <zdotdir>/.zshrc    — zsh interactive
# Default home: $HOME
# Default zdotdir: auto-detected via shell__detect_zdotdir
shell__user_init_files() {
  local _home="${HOME:-}" _zdotdir=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      --zdotdir)
        shift
        _zdotdir="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  [[ -z "$_zdotdir" ]] && _zdotdir="$(shell__detect_zdotdir --home "$_home")"
  shell__user_login_file --home "$_home"
  echo "${_home}/.bashrc"
  echo "${_zdotdir}/.zprofile"
  echo "${_zdotdir}/.zshrc"
  return 0
}

# shell__user_rc_files [--home <dir>] [--zdotdir <dir>]
# Prints user-scoped interactive shell rc file paths.
# One absolute path per line:
#   <home>/.bashrc    — bash interactive (non-login)
#   <zdotdir>/.zshrc  — zsh interactive
# Intended for initializers that must only run in interactive shells
# (e.g. conda init, shell prompt setup). Does NOT include login files
# (.bash_profile, .zprofile) — use shell__user_init_files for those.
# Default home: $HOME
# Default zdotdir: auto-detected via shell__detect_zdotdir
shell__user_rc_files() {
  local _home="${HOME:-}" _zdotdir=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --home)
        shift
        _home="$1"
        shift
        ;;
      --zdotdir)
        shift
        _zdotdir="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  [[ -z "$_zdotdir" ]] && _zdotdir="$(shell__detect_zdotdir --home "$_home")"
  echo "${_home}/.bashrc"
  echo "${_zdotdir}/.zshrc"
  return 0
}

# shell__system_rc_files
# Prints system-wide interactive shell rc file paths.
# One absolute path per line:
#   <global bashrc>           — bash interactive (distro-specific path)
#   <global zshdir>/zshrc     — zsh interactive
# Intended for system-wide conda init or similar interactive-only setup
# when no per-user targets are resolved (e.g. running as root with no
# resolved users). Does NOT include login files or PATH-export files.
shell__system_rc_files() {
  shell__detect_bashrc
  echo "$(shell__detect_zshdir)/zshrc"
  return 0
}

# shell__resolve_omz_theme --theme_slug <slug> --custom_dir <dir>
# Given an owner/repo theme slug and the ZSH_CUSTOM directory, prints the
# ZSH_THEME value that oh-my-zsh expects (e.g. "powerlevel10k/powerlevel10k").
# Prints the repo name alone if the theme file can't be found.
shell__resolve_omz_theme() {
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

# shell__plugin_names_from_slugs <comma-separated-slugs>
# Extracts the repo names (basenames) from a CSV of owner/repo slugs.
# Prints one name per line.
shell__plugin_names_from_slugs() {
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

# shell__resolve_home <username>
# Prints the home directory for the given user.
shell__resolve_home() {
  local _user="$1"
  eval echo "~${_user}"
  return 0
}

# shell__ensure_bashenv
# Detects or creates the system-wide BASH_ENV file and registers it in
# /etc/environment. Prints the absolute path to the file.
# Detection priority:
#   1. $BASH_ENV environment variable — already set, reuse as-is.
#   2. BASH_ENV= entry in /etc/environment — already registered, reuse.
#   3. Create <bashrc_dir>/bashenv, register BASH_ENV="<path>" in /etc/environment.
# Callers are responsible for writing content to the returned path.
shell__ensure_bashenv() {
  # 1. Live environment variable
  if [ -n "${BASH_ENV:-}" ]; then
    echo "ℹ️ BASH_ENV already set to '${BASH_ENV}'; reusing." >&2
    echo "$BASH_ENV"
    return 0
  fi
  # Allow tests (and callers) to override the path via _SHELL_ENV_FILE.
  local _env_file="${_SHELL_ENV_FILE:-/etc/environment}"
  # 2. Existing /etc/environment entry
  if [ -f "$_env_file" ]; then
    local _env_val
    _env_val="$(grep -m1 '^BASH_ENV=' "$_env_file" 2> /dev/null || true)"
    if [ -n "$_env_val" ]; then
      _env_val="${_env_val#BASH_ENV=}"
      _env_val="${_env_val#[\"\']}"
      _env_val="${_env_val%[\"\']}"
      echo "ℹ️ Found BASH_ENV='${_env_val}' in '${_env_file}'; reusing." >&2
      echo "$_env_val"
      return 0
    fi
  fi
  # 3. Create new bashenv file and register in /etc/environment
  local _bashrc
  _bashrc="$(shell__detect_bashrc)"
  local _bashenv_dir
  _bashenv_dir="$(dirname "$_bashrc")"
  local _bashenv_path="${_bashenv_dir}/bashenv"
  echo "ℹ️ No BASH_ENV found; creating '${_bashenv_path}' and registering in '${_env_file}'." >&2
  mkdir -p "$_bashenv_dir"
  [ -f "$_bashenv_path" ] || touch "$_bashenv_path"
  printf 'BASH_ENV="%s"\n' "$_bashenv_path" >> "$_env_file"
  echo "$_bashenv_path"
  return 0
}

# @brief shell__create_symlink --src <s> --system-target <t> --user-target <t> — Create a symlink, choosing system-wide or user-scoped location based on the src path.
#
# If <src> is under any user's home directory (as listed in /etc/passwd),
# places the symlink at <user-target>; otherwise at <system-target>. If src
# equals the chosen target, no symlink is needed and the function returns
# without error.
#
# Errors if the chosen target path is a real file or directory (not a symlink).
# Creates parent directories of the target as needed.
#
# Args:
#   --src <s>            The path the symlink will point to.
#   --system-target <t>  Symlink path for system-wide installations.
#   --user-target <t>    Symlink path for user-scoped installations.
shell__create_symlink() {
  local _src="" _system_target="" _user_target=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --src)
        shift
        _src="$1"
        shift
        ;;
      --system-target)
        shift
        _system_target="$1"
        shift
        ;;
      --user-target)
        shift
        _user_target="$1"
        shift
        ;;
      *) shift ;;
    esac
  done
  # Choose symlink target by checking if src is under any home dir in /etc/passwd.
  # getent is tried first (glibc systems); falls back to /etc/passwd directly
  # (Alpine/musl, macOS). Both always contain users created by useradd/adduser.
  # Allow tests (and callers) to override the passwd path via _SHELL_PASSWD_FILE.
  local _target="$_system_target"
  local _passwd_entries
  if [[ -n "${_SHELL_PASSWD_FILE:-}" ]]; then
    _passwd_entries="$(grep -v '^#' "$_SHELL_PASSWD_FILE")"
  else
    _passwd_entries="$(getent passwd 2> /dev/null || grep -v '^#' /etc/passwd)"
  fi
  local _home_dir
  while IFS=: read -r _ _ _ _ _ _home_dir _; do
    [[ -z "$_home_dir" ]] && continue
    if [[ "$_src" == "${_home_dir}/"* || "$_src" == "$_home_dir" ]]; then
      _target="$_user_target"
      break
    fi
  done <<< "$_passwd_entries"
  # If src and target are the same path, no symlink is needed.
  if [[ "$_src" == "$_target" ]]; then
    echo "ℹ️ src and target are identical ('${_target}'); no symlink needed." >&2
    return 0
  fi
  # Guard: refuse to clobber a real file or directory.
  if [[ -e "$_target" && ! -L "$_target" ]]; then
    echo "⛔ '${_target}' exists as a real file or directory; cannot create symlink." >&2
    return 1
  fi
  # Remove stale symlink before recreating.
  [[ -L "$_target" ]] && rm -f "$_target"
  mkdir -p "$(dirname "$_target")"
  ln -s "$_src" "$_target"
  echo "✅ Created symlink '${_target}' -> '${_src}'." >&2
  return 0
}
