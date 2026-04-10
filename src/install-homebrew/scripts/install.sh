#!/usr/bin/env bash
set -euo pipefail

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
_BASE_DIR="$(cd "$_SELF_DIR/.." && pwd)"

# ospkg.sh is sourced for net::* and os::* access.
# ospkg::detect (lazy) is only called on Linux, not macOS.
. "$_SELF_DIR/_lib/ospkg.sh"
. "$_SELF_DIR/_lib/logging.sh"
logging::setup
echo "↪️ Script entry: Homebrew Installation Devcontainer Feature Installer" >&2
trap 'logging::cleanup' EXIT

# ── High-level steps ──────────────────────────────────────────────────────────

install_linux_deps() {
  echo "↪️ Function entry: install_linux_deps" >&2
  echo "📦 Installing Homebrew build dependencies." >&2
  ospkg::run --manifest "${_BASE_DIR}/dependencies/base.txt" --check_installed
  echo "↩️ Function exit: install_linux_deps" >&2
  return 0
}

ensure_xcode_clt() {
  echo "↪️ Function entry: ensure_xcode_clt" >&2
  if xcode-select -p > /dev/null 2>&1; then
    echo "✅ Xcode Command Line Tools already installed at '$(xcode-select -p)'." >&2
    echo "↩️ Function exit: ensure_xcode_clt" >&2
    return 0
  fi
  echo "🔍 Xcode Command Line Tools not found — installing headlessly." >&2
  # Headless CLT install pattern: create sentinel, find the softwareupdate
  # package name, install, remove sentinel.
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  local _pkg
  _pkg="$(softwareupdate -l 2>&1 \
          | grep -E '\*.*Command Line Tools' \
          | tail -1 \
          | sed 's/.*\* //')" || true
  if [ -z "$_pkg" ]; then
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    echo "⛔ No 'Command Line Tools' package found in softwareupdate -l." >&2
    echo "   Install manually with: xcode-select --install" >&2
    exit 1
  fi
  echo "📦 Installing via softwareupdate: '${_pkg}'" >&2
  softwareupdate -i "$_pkg" --verbose
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  echo "✅ Xcode Command Line Tools installed." >&2
  echo "↩️ Function exit: ensure_xcode_clt" >&2
  return 0
}

run_brew_installer() {
  echo "↪️ Function entry: run_brew_installer" >&2
  echo "📦 Running Homebrew installer as user '${RESOLVED_INSTALL_USER}'." >&2
  local -a _env_vars=("NONINTERACTIVE=1")
  [ -n "${BREW_GIT_REMOTE-}"  ] && _env_vars+=("HOMEBREW_BREW_GIT_REMOTE=${BREW_GIT_REMOTE}")
  [ -n "${CORE_GIT_REMOTE-}"  ] && _env_vars+=("HOMEBREW_CORE_GIT_REMOTE=${CORE_GIT_REMOTE}")
  [[ "${NO_INSTALL_FROM_API}" == true ]] && _env_vars+=("HOMEBREW_NO_INSTALL_FROM_API=1")
  [ -n "${PREFIX-}"           ] && _env_vars+=("HOMEBREW_PREFIX=${PREFIX}")
  local _installer_url="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
  local _tmpfile
  _tmpfile="$(mktemp /tmp/brew_install.XXXXXX.sh)"
  # shellcheck disable=SC2064
  trap "rm -f '${_tmpfile}'" RETURN
  net::ensure_fetch_tool
  net::ensure_ca_certs
  echo "📥 Downloading Homebrew installer to '${_tmpfile}'." >&2
  net::fetch_url_file "$_installer_url" "$_tmpfile"
  if [ "$(id -u)" = "0" ] && [ "$RESOLVED_INSTALL_USER" != "root" ]; then
    echo "ℹ️ Installing as '${RESOLVED_INSTALL_USER}' via sudo." >&2
    sudo -u "$RESOLVED_INSTALL_USER" env "${_env_vars[@]}" /bin/bash "$_tmpfile"
  else
    env "${_env_vars[@]}" /bin/bash "$_tmpfile"
  fi
  echo "✅ Homebrew installer completed." >&2
  echo "↩️ Function exit: run_brew_installer" >&2
  return 0
}

uninstall_brew() {
  echo "↪️ Function entry: uninstall_brew" >&2
  echo "🗑 Uninstalling Homebrew at '${RESOLVED_PREFIX}'." >&2
  local _uninstall_url="https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh"
  local _tmpfile
  _tmpfile="$(mktemp /tmp/brew_uninstall.XXXXXX.sh)"
  # shellcheck disable=SC2064
  trap "rm -f '${_tmpfile}'" RETURN
  net::fetch_url_file "$_uninstall_url" "$_tmpfile"
  if [ "$(id -u)" = "0" ] && [ "$RESOLVED_INSTALL_USER" != "root" ]; then
    sudo -u "$RESOLVED_INSTALL_USER" env NONINTERACTIVE=1 /bin/bash "$_tmpfile" \
      --path "$RESOLVED_PREFIX"
  else
    NONINTERACTIVE=1 /bin/bash "$_tmpfile" --path "$RESOLVED_PREFIX"
  fi
  echo "✅ Homebrew uninstalled." >&2
  echo "↩️ Function exit: uninstall_brew" >&2
  return 0
}

write_shellenv_block() {
  echo "↪️ Function entry: write_shellenv_block" >&2
  local target_file="$1"
  local brew_bin="${RESOLVED_PREFIX}/bin/brew"
  local begin_marker="# >>> brew shellenv (install-homebrew) >>>"
  local end_marker="# <<< brew shellenv (install-homebrew) <<<"
  local block_content
  block_content='eval "$('"${brew_bin}"' shellenv)"'
  mkdir -p "$(dirname "$target_file")"
  [ -f "$target_file" ] || touch "$target_file"
  if grep -qF "$begin_marker" "$target_file"; then
    awk -v begin="$begin_marker" -v end="$end_marker" -v content="$block_content" '
      $0 == begin { print; print content; found=1; next }
      found && $0 == end { print; found=0; next }
      found { next }
      { print }
    ' "$target_file" > "${target_file}.tmp" && mv "${target_file}.tmp" "$target_file"
    echo "♻️ Updated shellenv block in '${target_file}'." >&2
  else
    printf '\n%s\n%s\n%s\n' "$begin_marker" "$block_content" "$end_marker" >> "$target_file"
    echo "✅ Appended shellenv block to '${target_file}'." >&2
  fi
  echo "↩️ Function exit: write_shellenv_block" >&2
  return 0
}

export_shellenv_for_user() {
  echo "↪️ Function entry: export_shellenv_for_user" >&2
  local _user="$1"
  local _home
  _home="$(getent passwd "$_user" 2>/dev/null | cut -d: -f6)" \
    || _home="$(eval echo "~${_user}" 2>/dev/null)" \
    || { echo "⚠️ Could not determine home directory for user '${_user}'. Skipping." >&2; return 0; }

  # Login bash: pick the first existing file, or fall back to .bash_profile
  local _login_file=""
  for _f in "${_home}/.bash_profile" "${_home}/.bash_login" "${_home}/.profile"; do
    [ -f "$_f" ] && { _login_file="$_f"; break; }
  done
  [ -z "$_login_file" ] && _login_file="${_home}/.bash_profile"

  # Non-login interactive bash
  local _bashrc="${_home}/.bashrc"

  # Zsh: prefer .zprofile (login) and .zshrc (interactive); on macOS Terminal
  # opens login shells so .zprofile is the primary PATH injection point.
  local _zprofile="${_home}/.zprofile"
  local _zshrc="${_home}/.zshrc"

  for _target in "$_login_file" "$_bashrc" "$_zprofile" "$_zshrc"; do
    write_shellenv_block "$_target"
  done
  echo "↩️ Function exit: export_shellenv_for_user" >&2
  return 0
}

export_shellenv_main() {
  echo "↪️ Function entry: export_shellenv_main" >&2
  if [ "$EXPORT_PATH" = "" ]; then
    echo "ℹ️ export_path is empty; skipping shellenv export." >&2
    echo "↩️ Function exit: export_shellenv_main" >&2
    return 0
  fi
  if [ "$EXPORT_PATH" != "auto" ]; then
    # Explicit newline-separated path list
    while IFS= read -r _f; do
      [ -z "$_f" ] && continue
      write_shellenv_block "$_f"
    done <<< "$EXPORT_PATH"
    echo "↩️ Function exit: export_shellenv_main" >&2
    return 0
  fi
  # auto mode
  local _is_root=false
  [ "$(id -u)" = "0" ] && _is_root=true
  local _platform
  _platform="$(detect_platform)"
  if [ "$_is_root" = true ] && [ "$(uname -s)" != "Darwin" ]; then
    echo "ℹ️ Case A: system-wide shellenv export (root + Linux)." >&2
    # /etc/profile.d/brew.sh — login shells
    write_shellenv_block "/etc/profile.d/brew.sh"
    # Global bashrc — non-login interactive bash
    local _bashrc=""
    for _f in /etc/bash.bashrc /etc/bashrc /etc/bash/bashrc; do
      [ -f "$_f" ] && { _bashrc="$_f"; break; }
    done
    [ -z "$_bashrc" ] && _bashrc="$(_platform_bashrc "$_platform")"
    write_shellenv_block "$_bashrc"
    # Global zshenv — all zsh sessions
    local _zshenv=""
    for _f in /etc/zsh/zshenv /etc/zshenv; do
      [ -f "$_f" ] && { _zshenv="$_f"; break; }
    done
    [ -z "$_zshenv" ] && _zshenv="$(_platform_zshenv "$_platform")"
    write_shellenv_block "$_zshenv"
  else
    echo "ℹ️ Case B: user-scoped shellenv export." >&2
    export_shellenv_for_user "$RESOLVED_INSTALL_USER"
  fi
  # Additional users
  if [ -n "${USERS-}" ]; then
    IFS=',' read -ra _EXTRA_USERS <<< "$USERS"
    for _u in "${_EXTRA_USERS[@]}"; do
      [[ -z "$_u" ]] && continue
      echo "ℹ️ Exporting shellenv for additional user '${_u}'." >&2
      export_shellenv_for_user "$_u"
    done
  fi
  echo "↩️ Function exit: export_shellenv_main" >&2
  return 0
}

# ── Helper functions ──────────────────────────────────────────────────────────

detect_platform() {
  echo "↪️ Function entry: detect_platform" >&2
  local id="" id_like=""
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    id_like="${ID_LIKE:-}"
  fi
  case "$id" in
    debian|ubuntu)                            echo "debian"; echo "↩️ Function exit: detect_platform" >&2; return 0 ;;
    alpine)                                   echo "alpine"; echo "↩️ Function exit: detect_platform" >&2; return 0 ;;
    rhel|centos|fedora|rocky|almalinux)       echo "rhel";   echo "↩️ Function exit: detect_platform" >&2; return 0 ;;
  esac
  case "$id_like" in
    *debian*|*ubuntu*)                        echo "debian"; echo "↩️ Function exit: detect_platform" >&2; return 0 ;;
    *alpine*)                                 echo "alpine"; echo "↩️ Function exit: detect_platform" >&2; return 0 ;;
    *rhel*|*fedora*|*centos*|*"Red Hat"*)     echo "rhel";   echo "↩️ Function exit: detect_platform" >&2; return 0 ;;
  esac
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "macos"; echo "↩️ Function exit: detect_platform" >&2; return 0
  fi
  echo "debian"  # fallback
  echo "↩️ Function exit: detect_platform" >&2
  return 0
}

_platform_bashrc() {
  local platform="$1"
  case "$platform" in
    alpine)      echo "/etc/bash/bashrc" ;;
    rhel|macos)  echo "/etc/bashrc" ;;
    *)           echo "/etc/bash.bashrc" ;;
  esac
  return 0
}

_platform_zshenv() {
  local platform="$1"
  case "$platform" in
    rhel|macos)  echo "/etc/zshenv" ;;
    *)           echo "/etc/zsh/zshenv" ;;
  esac
  return 0
}

detect_brew_prefix() {
  echo "↪️ Function entry: detect_brew_prefix" >&2
  if [ "$(uname -s)" = "Darwin" ]; then
    if [ "$(uname -m)" = "arm64" ]; then
      echo "/opt/homebrew"
    else
      echo "/usr/local"
    fi
  else
    echo "/home/linuxbrew/.linuxbrew"
  fi
  echo "↩️ Function exit: detect_brew_prefix" >&2
  return 0
}

detect_install_user() {
  echo "↪️ Function entry: detect_install_user" >&2
  if [ -n "${INSTALL_USER-}" ]; then
    echo "ℹ️ Using specified install_user: '${INSTALL_USER}'." >&2
    echo "$INSTALL_USER"
    echo "↩️ Function exit: detect_install_user" >&2
    return 0
  fi
  if [ "$(id -u)" != "0" ]; then
    id -nu
    echo "↩️ Function exit: detect_install_user" >&2
    return 0
  fi
  # Running as root.
  if [ "$(uname -s)" = "Darwin" ]; then
    # The official Homebrew installer refuses to run as root on macOS.
    # We must find a non-root user to install as.
    if [ -n "${SUDO_USER-}" ] && [ "$SUDO_USER" != "root" ]; then
      echo "ℹ️ macOS root: using SUDO_USER='${SUDO_USER}' as install_user." >&2
      echo "$SUDO_USER"
    else
      local _u
      _u="$(dscl . list /Users 2>/dev/null \
            | grep -v -E '^(_|daemon|nobody|root|Guest)' \
            | head -1)" || true
      if [ -n "$_u" ]; then
        echo "ℹ️ macOS root: using first non-system user '${_u}' as install_user." >&2
        echo "$_u"
      else
        echo "⛔ Running as root on macOS but no non-root user found." >&2
        echo "   Set the 'install_user' option to a non-root user account." >&2
        exit 1
      fi
    fi
  else
    # Linux: root installs are supported by the Homebrew installer.
    if [ -n "${SUDO_USER-}" ] && [ "$SUDO_USER" != "root" ]; then
      echo "ℹ️ Linux root: using SUDO_USER='${SUDO_USER}' as install_user." >&2
      echo "$SUDO_USER"
    else
      echo "ℹ️ Linux root: installing as root." >&2
      echo "root"
    fi
  fi
  echo "↩️ Function exit: detect_install_user" >&2
  return 0
}

# ── Argument parsing (dual-mode: env vars or CLI flags) ───────────────────────
if [[ "$#" -gt 0 ]]; then
  INSTALL_USER=""
  PREFIX=""
  IF_EXISTS=""
  UPDATE=""
  EXPORT_PATH=""
  USERS=""
  BREW_GIT_REMOTE=""
  CORE_GIT_REMOTE=""
  NO_INSTALL_FROM_API=""
  DEBUG=""
  LOGFILE=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --install_user)         shift; INSTALL_USER="$1";         echo "📩 Read argument 'install_user': '${INSTALL_USER}'" >&2;                   shift;;
      --prefix)               shift; PREFIX="$1";               echo "📩 Read argument 'prefix': '${PREFIX}'" >&2;                               shift;;
      --if_exists)            shift; IF_EXISTS="$1";            echo "📩 Read argument 'if_exists': '${IF_EXISTS}'" >&2;                         shift;;
      --update)               shift; UPDATE="$1";               echo "📩 Read argument 'update': '${UPDATE}'" >&2;                               shift;;
      --export_path)          shift; EXPORT_PATH="$1";          echo "📩 Read argument 'export_path': '${EXPORT_PATH}'" >&2;                     shift;;
      --users)                shift; USERS="$1";                echo "📩 Read argument 'users': '${USERS}'" >&2;                                 shift;;
      --brew_git_remote)      shift; BREW_GIT_REMOTE="$1";      echo "📩 Read argument 'brew_git_remote': '${BREW_GIT_REMOTE}'" >&2;             shift;;
      --core_git_remote)      shift; CORE_GIT_REMOTE="$1";      echo "📩 Read argument 'core_git_remote': '${CORE_GIT_REMOTE}'" >&2;             shift;;
      --no_install_from_api)  shift; NO_INSTALL_FROM_API="$1";  echo "📩 Read argument 'no_install_from_api': '${NO_INSTALL_FROM_API}'" >&2;     shift;;
      --debug)                shift; DEBUG="$1";                echo "📩 Read argument 'debug': '${DEBUG}'" >&2;                                 shift;;
      --logfile)              shift; LOGFILE="$1";              echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2;                             shift;;
      --*) echo "⛔ Unknown option: '${1}'" >&2; exit 1;;
      *)   echo "⛔ Unexpected argument: '${1}'" >&2; exit 1;;
    esac
  done
else
  echo "ℹ️ Script called with no arguments. Reading environment variables." >&2
  [ "${INSTALL_USER+defined}"        ] && echo "📩 Read argument 'install_user': '${INSTALL_USER}'" >&2
  [ "${PREFIX+defined}"              ] && echo "📩 Read argument 'prefix': '${PREFIX}'" >&2
  [ "${IF_EXISTS+defined}"           ] && echo "📩 Read argument 'if_exists': '${IF_EXISTS}'" >&2
  [ "${UPDATE+defined}"              ] && echo "📩 Read argument 'update': '${UPDATE}'" >&2
  [ "${EXPORT_PATH+defined}"         ] && echo "📩 Read argument 'export_path': '${EXPORT_PATH}'" >&2
  [ "${USERS+defined}"               ] && echo "📩 Read argument 'users': '${USERS}'" >&2
  [ "${BREW_GIT_REMOTE+defined}"     ] && echo "📩 Read argument 'brew_git_remote': '${BREW_GIT_REMOTE}'" >&2
  [ "${CORE_GIT_REMOTE+defined}"     ] && echo "📩 Read argument 'core_git_remote': '${CORE_GIT_REMOTE}'" >&2
  [ "${NO_INSTALL_FROM_API+defined}" ] && echo "📩 Read argument 'no_install_from_api': '${NO_INSTALL_FROM_API}'" >&2
  [ "${DEBUG+defined}"               ] && echo "📩 Read argument 'debug': '${DEBUG}'" >&2
  [ "${LOGFILE+defined}"             ] && echo "📩 Read argument 'logfile': '${LOGFILE}'" >&2
fi

[[ "${DEBUG-}" == true ]] && set -x

[ -z "${INSTALL_USER-}"        ] && { echo "ℹ️ Argument 'INSTALL_USER' set to default value ''." >&2;                    INSTALL_USER=""; }
[ -z "${PREFIX-}"              ] && { echo "ℹ️ Argument 'PREFIX' set to default value ''." >&2;                          PREFIX=""; }
[ -z "${IF_EXISTS-}"           ] && { echo "ℹ️ Argument 'IF_EXISTS' set to default value 'skip'." >&2;                   IF_EXISTS="skip"; }
[ -z "${UPDATE-}"              ] && { echo "ℹ️ Argument 'UPDATE' set to default value 'true'." >&2;                      UPDATE=true; }
[ -z "${EXPORT_PATH+x}"        ] && { echo "ℹ️ Argument 'EXPORT_PATH' set to default value 'auto'." >&2;                 EXPORT_PATH="auto"; }
[ -z "${USERS-}"               ] && { echo "ℹ️ Argument 'USERS' set to default value ''." >&2;                           USERS=""; }
[ -z "${BREW_GIT_REMOTE-}"     ] && { echo "ℹ️ Argument 'BREW_GIT_REMOTE' set to default value ''." >&2;                 BREW_GIT_REMOTE=""; }
[ -z "${CORE_GIT_REMOTE-}"     ] && { echo "ℹ️ Argument 'CORE_GIT_REMOTE' set to default value ''." >&2;                 CORE_GIT_REMOTE=""; }
[ -z "${NO_INSTALL_FROM_API-}" ] && { echo "ℹ️ Argument 'NO_INSTALL_FROM_API' set to default value 'false'." >&2;        NO_INSTALL_FROM_API=false; }
[ -z "${DEBUG-}"               ] && { echo "ℹ️ Argument 'DEBUG' set to default value 'false'." >&2;                      DEBUG=false; }
[ -z "${LOGFILE-}"             ] && { echo "ℹ️ Argument 'LOGFILE' set to default value ''." >&2;                         LOGFILE=""; }

echo "========================================" >&2
echo "  install-homebrew" >&2
echo "========================================" >&2

# ── Resolve prefix and install user ──────────────────────────────────────────
if [ -n "$PREFIX" ]; then
  RESOLVED_PREFIX="$PREFIX"
  echo "ℹ️ Using explicit prefix: '${RESOLVED_PREFIX}'." >&2
elif command -v brew > /dev/null 2>&1; then
  RESOLVED_PREFIX="$(brew --prefix)"
  echo "ℹ️ Detected existing brew prefix: '${RESOLVED_PREFIX}'." >&2
else
  RESOLVED_PREFIX="$(detect_brew_prefix)"
  echo "ℹ️ Using platform-default prefix: '${RESOLVED_PREFIX}'." >&2
fi

RESOLVED_INSTALL_USER="$(detect_install_user)"
echo "ℹ️ Install user: '${RESOLVED_INSTALL_USER}'." >&2

# ── Step 1: Linux build dependencies ─────────────────────────────────────────
if [ "$(uname -s)" != "Darwin" ]; then
  install_linux_deps
fi

# ── Step 2: macOS — Xcode Command Line Tools ──────────────────────────────────
if [ "$(uname -s)" = "Darwin" ]; then
  ensure_xcode_clt
fi

# ── Step 3: Install / skip / reinstall Homebrew ───────────────────────────────
_BREW_EXEC="${RESOLVED_PREFIX}/bin/brew"
if [ -f "$_BREW_EXEC" ]; then
  echo "⚠️ Homebrew found at '${_BREW_EXEC}'." >&2
  case "$IF_EXISTS" in
    skip)
      echo "⏭️ if_exists=skip: existing Homebrew detected; skipping installer and continuing to post-install steps." >&2
      ;;
    fail)
      echo "⛔ if_exists=fail: Homebrew already installed at '${RESOLVED_PREFIX}'." >&2
      echo "   Remove it first or set if_exists=skip or if_exists=reinstall." >&2
      exit 1
      ;;
    reinstall)
      echo "ℹ️ if_exists=reinstall: uninstalling then reinstalling Homebrew." >&2
      uninstall_brew
      run_brew_installer
      ;;
    *)
      echo "⛔ Invalid value for 'if_exists': '${IF_EXISTS}'. Use 'skip', 'fail', or 'reinstall'." >&2
      exit 1
      ;;
  esac
else
  run_brew_installer
fi

# ── Step 4: Verify brew executable ───────────────────────────────────────────
if [ ! -f "$_BREW_EXEC" ]; then
  echo "⛔ Homebrew executable not found at '${_BREW_EXEC}' after installation." >&2
  exit 1
fi
echo "✅ Homebrew $("$_BREW_EXEC" --version | head -1) is available at '${_BREW_EXEC}'." >&2

# ── Step 5: brew update ───────────────────────────────────────────────────────
if [[ "$UPDATE" == true ]]; then
  echo "🔄 Running 'brew update'." >&2
  if [ "$(id -u)" = "0" ] && [ "$RESOLVED_INSTALL_USER" != "root" ]; then
    sudo -u "$RESOLVED_INSTALL_USER" "$_BREW_EXEC" update
  else
    "$_BREW_EXEC" update
  fi
  echo "✅ brew update completed." >&2
fi

# ── Step 6: Export shellenv ───────────────────────────────────────────────────
export_shellenv_main

# ── Step 7: brew doctor (warn only) ──────────────────────────────────────────
echo "ℹ️ Running 'brew doctor' (warnings only)." >&2
if [ "$(id -u)" = "0" ] && [ "$RESOLVED_INSTALL_USER" != "root" ]; then
  sudo -u "$RESOLVED_INSTALL_USER" "$_BREW_EXEC" doctor 2>&1 || true
else
  "$_BREW_EXEC" doctor 2>&1 || true
fi

echo "✅ Homebrew installation complete." >&2
echo "↩️ Script exit: Homebrew Installation Devcontainer Feature Installer" >&2

